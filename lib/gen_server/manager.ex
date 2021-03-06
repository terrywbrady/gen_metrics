defmodule GenMetrics.GenServer.Manager do
  alias GenMetrics.GenServer.Manager
  alias GenMetrics.GenServer.Server
  alias GenMetrics.GenServer.Summary
  alias GenMetrics.GenServer.Stats
  alias GenMetrics.GenServer.Window
  alias GenMetrics.GenServer.Metric
  alias GenMetrics.Utils.Math
  alias GenMetrics.Utils.Runtime
  alias GenMetrics.Utils.StatsPush

  @moduledoc false

  @call_cast_info [:handle_call, :handle_cast, :handle_info]

  defstruct servers: %{}, summary_partials: %{}, summary_paired: %{},
    stats_partials: %{}, stats_paired: %{}

  def initialize do
    %Manager{}
  end

  def reinitialize(metrics) do
    %Manager{servers: metrics.servers,
             summary_partials: metrics.summary_partials,
             stats_partials: metrics.stats_partials}
  end

  def open_summary_metric(metrics, mod, pid, fun, ts) do
    metrics = register_pid_on_server(metrics, mod, pid)
    do_open_summary_metric(metrics, mod, pid, fun, ts)
  end

  def close_summary_metric(metrics, pid, events, ts) do
    do_close_summary_metric(metrics, pid, events, ts)
  end

  def open_stats_metric(metrics, {mod, pid, fun, ts}) do
    metrics = register_pid_on_server(metrics, mod, pid)
    do_open_stats_metric(metrics, {pid, fun, ts})
  end

  def close_stats_metric(cluster, metrics, {mod, pid, events, ts}) do
    do_close_stats_metric(cluster, metrics, {mod, pid, events, ts})
  end

  def as_window(metrics, gen_stats, sample_rate) do
    window = %Window{summary: build_server_summary(metrics, sample_rate)}
    if gen_stats do
      with server_metrics <- build_server_metrics(metrics),
           server_stats <- build_server_stats(server_metrics, sample_rate),
      do: %Window{window | stats: server_stats}
    else
      window
    end
  end

  #
  # Metrics manager private utility functions follow.
  #

  defp register_pid_on_server(metrics, server, pid) do
    servers = Map.update(metrics.servers, server,
      MapSet.new |> MapSet.put(pid), & MapSet.put(&1, pid))
    %Manager{metrics | servers: servers}
  end

  defp do_open_summary_metric(metrics, _mod, pid, fun, ts) do
    mkey = as_metric_key(pid, fun)
    mevent = Metric.partial(ts)
    summary_partials = Map.put(metrics.summary_partials, mkey, mevent)
    %Manager{metrics | summary_partials: summary_partials}
  end

  defp do_close_summary_metric(metrics, pid, fun, ts) do
    mkey = as_metric_key(pid, fun)
    if Map.has_key?(metrics.summary_partials, mkey) do
      {partial, summary_partials} = Map.pop(metrics.summary_partials, mkey)
      summary_paired = Metric.pair(metrics.summary_paired, mkey, ts, partial)
      %Manager{metrics | summary_partials: summary_partials,
               summary_paired: summary_paired}
    else
      metrics
    end
  end

  defp do_open_stats_metric(metrics, {pid, fun, ts}) do
    mkey = as_metric_key(pid, fun)
    mevent = Metric.start(ts)
    stats_partials = Map.put(metrics.stats_partials, mkey, mevent)
    %Manager{metrics | stats_partials: stats_partials}
  end

  defp do_close_stats_metric(cluster, metrics, {mod, pid, fun, ts}) do
    mkey = as_metric_key(pid, fun)
    if Map.has_key?(metrics.stats_partials, mkey) do
      {partial, partials} = Map.pop(metrics.stats_partials, mkey)
      mevent = Metric.stop(partial, ts)
      statsd_args = {mod, pid, fun, mevent, partials}
      case cluster.opts[:statistics] do
        :statsd  ->
          push_metric_to_statsd(cluster, metrics, statsd_args)
        :datadog ->
          push_metric_to_datadog(cluster, metrics, statsd_args)
        _        ->
          push_metric_in_memory(cluster, metrics, mkey, mevent, partials)
      end
    else
      metrics
    end
  end

  defp build_server_summary(metrics, sample_rate) do
    for {server, pids} <- metrics.servers, pid <- pids, into: [] do
      mkeys = for key <- @call_cast_info, do: as_metric_key(pid, key)
      metrics_on_pid = for mkey <- mkeys do
        Map.get(metrics.summary_paired, mkey, Metric.no_pair)
      end
      summary = generate_server_summary(metrics_on_pid, sample_rate)
      %Summary{summary | name: server, pid: pid}
    end
  end

  defp build_server_metrics(metrics) do
    for {server, pids} <- metrics.servers, pid <- pids, into: [] do
      mkeys = for key <- @call_cast_info, do: as_metric_key(pid, key)
      {server, pid,
       (for mkey <- mkeys, do: Map.get(metrics.stats_paired, mkey, []))}
    end
  end

  defp build_server_stats([], _), do: []
  defp build_server_stats(server_metrics, sample_rate) do
    for {module, pid, [calls, casts, infos]} <- server_metrics do
      %Server{name: module, pid: pid,
              calls: generate_metric_stats(calls, length(calls), sample_rate),
              casts: generate_metric_stats(casts, length(casts), sample_rate),
              infos: generate_metric_stats(infos, length(infos), sample_rate)}
    end
  end

  defp generate_server_summary([calls, casts, infos], sample_rate) do
    do_generate_server_summary(calls, casts, infos, sample_rate)
  end

  defp generate_server_summary(server = %Server{}, sample_rate) do
    calls = {server.calls.calls, server.calls.total, 0}
    casts = {server.casts.calls, server.casts.total, 0}
    infos = {server.infos.calls, server.casts.total, 0}
    do_generate_server_summary(calls, casts, infos, sample_rate)
  end

  defp do_generate_server_summary({calls, tcalls}, {casts, tcasts},
    {infos, tinfos}, sample_rate) do
    srate_multiplier = 1 / sample_rate
    %Summary{calls: round(calls * srate_multiplier),
             casts: round(casts * srate_multiplier),
             infos: round(infos * srate_multiplier),
             time_on_calls: Runtime.nano_to_milli(round(tcalls * srate_multiplier)),
             time_on_casts: Runtime.nano_to_milli(round(tcasts * srate_multiplier)),
             time_on_infos: Runtime.nano_to_milli(round(tinfos * srate_multiplier))}
  end

  defp generate_metric_stats([], _, sample_rate), do: generate_stats([], 0, sample_rate)
  defp generate_metric_stats(metrics, len, sample_rate) do
    metric_durations =
      metrics |> Enum.map(fn metric -> metric.duration end) |> Enum.sort
    generate_stats(metric_durations, len, sample_rate)
  end

  defp generate_stats(data, len, sample_rate) do
    srate_multiplier = 1 / sample_rate
    %Stats{callbacks: round(len * srate_multiplier),
           min: Math.min(data), max: Math.max(data),
           total: round(Math.sum(data) * srate_multiplier),
           mean: Math.mean(data, len),
           stdev: Math.stdev(data, len), range: Math.range(data)}
  end

  defp push_metric_in_memory(_cluster, metrics, mkey, mevent, stats_partials) do
    stats_paired =
      Map.update(metrics.stats_paired, mkey, [mevent], & [mevent | &1])
    %Manager{metrics | stats_partials: stats_partials,
             stats_paired: stats_paired}
  end

  defp push_metric_to_statsd(cluster, metrics, {mod, pid, fun, mevent, partials}) do
    StatsPush.statsd(cluster.name, mod, pid, fun, mevent)
    %Manager{metrics | stats_partials: partials}
  end

  defp push_metric_to_datadog(cluster, metrics, {mod, pid, fun, mevent, partials}) do
    StatsPush.datadog(cluster.name, mod, pid, fun, mevent)
    %Manager{metrics | stats_partials: partials}
  end

  defp as_metric_key(pid, fun) do
    "#{inspect pid}-#{inspect fun}"
  end

end
