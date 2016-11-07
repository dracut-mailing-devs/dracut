# Try to find out kernel modules with large total memory allocation during loading.
# For large slab allocation, it will fall into buddy, thus tracing "mm_page_alloc"
# alone should be enough for the purpose.

# "sys/kernel/tracing" has the priority if exists.
get_trace_base() {
    # trace access through debugfs would be obsolete if "/sys/kernel/tracing" is available.
    if [[ -d "/sys/kernel/tracing" ]]; then
        echo "/sys/kernel"
    else
        echo "/sys/kernel/debug"
    fi
}

# We want to enable these trace events.
get_want_events() {
    echo "module:module_put module:module_load kmem:mm_page_alloc"
}

get_event_filter() {
    echo "comm == systemd-udevd || comm == modprobe || comm == insmod"
}

is_trace_ready() {
    local trace_base want_events current_events

    trace_base=$(get_trace_base)
    ! [[ -f "$trace_base/tracing/trace" ]] && return 1

    [[ $(cat $trace_base/tracing/tracing_on) = 0 ]] && return 1

     # Also check if trace events were properly setup.
    want_events=$(get_want_events)
    current_events=$(echo $(cat $trace_base/tracing/set_event))
    [[ "$current_events" != "$want_events" ]] && return 1

    return 0
}

prepare_trace() {
    local trace_base

    trace_base=$(get_trace_base)
    # old debugfs interface case.
    if ! [[ -d "$trace_base/tracing" ]]; then
        mount none -t debugfs $trace_base
    # new tracefs interface case.
    elif ! [[ -f "$trace_base/tracing/trace" ]]; then
        mount none -t tracefs "$trace_base/tracing"
    fi

    if ! [[ -f "$trace_base/tracing/trace" ]]; then
        echo "WARN: Mount trace failed for kernel module memory analyzing."
        return
    fi

    # Active all the wanted trace events.
    echo "$(get_want_events)" > $trace_base/tracing/set_event

    # There are three kinds of known applications for module loading:
    # "systemd-udevd", "modprobe" and "insmod".
    # Set them as the global events filter.
    # NOTE: Some kernel may not support this format of filter, anyway
    #       the operation will fail and it doesn't matter.
    echo "$(get_event_filter)" > $trace_base/tracing/events/kmem/filter
    echo "$(get_event_filter)" > $trace_base/tracing/events/module/filter

    # Set the number of comm-pid if supported.
    if [[ -f "$trace_base/tracing/saved_cmdlines_size" ]]; then
        # Thanks to filters, 4096 is big enough(also well supported).
        echo 4096 > $trace_base/tracing/saved_cmdlines_size
    fi

    # Enable and clear trace data for the first time.
    echo 1 > $trace_base/tracing/tracing_on
    echo > $trace_base/tracing/trace
    echo "Prepare trace success."
}

parse_trace_data() {
    local module_name
    # Indexed by task pid.
    local -A current_module
    # Indexed by module name.
    local -A module_loaded
    local -A nr_alloc_pages

    cat "$(get_trace_base)/tracing/trace" | while read pid cpu flags ts function
    do
        # Skip comment lines
        if [[ $pid = "#" ]]; then
            continue
        fi

        if [[ $function = module_load* ]]; then
            # One module is being loaded, save the task pid for tracking.
            module_name=${function#*: }
            # Remove the trailing after whitespace, there may be the module flags.
            module_name=${module_name%% *}
            # Mark current_module to track the task.
            current_module[$pid]="$module_name"
            [[ ${module_loaded[$module_name]} ]] && echo "WARN: \"$module_name\" was loaded multiple times!"
            unset module_loaded[$module_name]
            nr_alloc_pages[$module_name]=0
            continue
        fi

        if ! [[ ${current_module[$pid]} ]]; then
            continue
        fi

        # Once we get here, the task is being tracked(is loading a module).
        # Get the module name.
        module_name=${current_module[$pid]}

        if [[ $function = module_put* ]]; then
            # Mark the module as loaded when the first module_put event happens after module_load.
            echo "${nr_alloc_pages[$module_name]} pages consumed by \"$module_name\""
            module_loaded[$module_name]=1
            # Module loading finished, so untrack the task.
            unset current_module[$pid]
            continue
        fi

        if [[ $function = mm_page_alloc* ]]; then
            order=$(echo $function | sed -e 's/.*order=\([0-9]*\) .*/\1/')
            nr_alloc_pages[$module_name]=$((${nr_alloc_pages[$module_name]}+$((2 ** $order))))
        fi
    done
}

cleanup_trace() {
    local trace_base

    if is_trace_ready; then
        trace_base=$(get_trace_base)
        echo 0 > $trace_base/tracing/tracing_on
        echo > $trace_base/tracing/trace
        echo > $trace_base/tracing/set_event
        echo 0 > $trace_base/tracing/events/kmem/filter
        echo 0 > $trace_base/tracing/events/module/filter
    fi
}

show_usage() {
    echo "Find out kernel modules with large memory consumption during loading."
    echo "Usage:"
    echo "1) run it first to setup trace."
    echo "2) run again to parse the trace data if any."
    echo "3) run with \"--cleanup\" option to cleanup trace after use."
}

if [[ $1 = "--help" ]]; then
    show_usage
    exit 0
fi


if [[ $1 = "--cleanup" ]]; then
    cleanup_trace
    exit 0
fi

if is_trace_ready ; then
    echo "tracekomem - Rough memory consumption by loading kernel modules (larger value with better accuracy)"
    parse_trace_data
else
    prepare_trace
fi
