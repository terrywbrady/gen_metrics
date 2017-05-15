defmodule GenMetrics do

  @moduledoc """
  Runtime metrics for `GenServer` and `GenStage` applications.

  **Important:**
  The GenMetrics library is not suitable for use within long-running
  production environments. For further details, see the [benchmarks
  performance guide](https://github.com/onetapbeyond/gen_metrics#benchmarks).

  This library supports the collection and publication of GenServer and GenStage
  runtime metrics. Metrics data are generated by an introspection agent. No
  instrumentation is required within the GenServer or GenStage library
  or within your application source code.

  GenMetrics data can be used to reveal insights into live application
  performance and identify patterns of behaviour within an application over
  time. Metrics data can be used to drive any number of operational systems,
  including realtime dashboards, monitoring and alerting systems.

  By default, metrics are published by a dedicated GenMetrics reporting process.
  Any application can subscribe to this process in order to aggregate, render,
  persist, or generally handle metrics data. Metrics data can also be pushed
  directly to a `statsd` agent which makes it possible to analyze, and visualize
  the metrics within existing tools and services like `Graphana` and `Datadog`.

  The metrics data collected by this library includes both summary metrics and
  optional detailed statistical metrics. Summary metrics and statistical
  metrics for GenServer and GenStage applications are described in detail below.

  ## GenMetrics Installation

  Simply add `gen_metrics` as a `deps` dependency in your Mixfile.

  ## GenMetrics for GenServer Applications

  Any application using the `GenServer` behaviour can immediately benefit from
  the insights afforded by GenMetrics. The following sections explain how.
  For `GenStage` applications, see the docs
  [here](#module-genmetrics-for-genstage-applications).

  ### GenServer Metrics Activation

  A `GenMetrics.GenServer.Cluster` struct is used to identify one or more
  GenServer modules that become candidates for metrics collection. For example,
  assuming your application has a `Session.Server` and a `Logging.Server` you
  can activate metrics collection on both GenServers as follows:

  ```
  alias GenMetrics.GenServer.Cluster
  cluster = %Cluster{name: "demo", servers: [Session.Server, Logging.Server]}
  GenMetrics.monitor_cluster(cluster)
  ```

  The *cluster* in this context is simply a named set of one or more GenServer
  modules about which you would like to collect metrics data. Metrics data
  are collected on server processes executing on the local node.

  GenMetrics will instantly attach to running GenServer processes associated
  with your cluster. If there are no running server processes associated with
  your cluster when `GenMetrics.monitor_cluster/1` is called, GenMetrics will
  monitor for process activation and automatically begin metrics collection
  for each new process.

  ### GenServer Metrics Sampling

  Sampling metrics is a effective way to collect and report metrics for any
  server while minimizing the runtime overhead introduced by the GenMetics
  monitoring agent.

  When sampling is disabled, metrics data reflect the exact behaviour of the
  processes being monitored. When sampling is enabled, metrics data reflect
  an approximation of the behaviour of the processes being monitored.

  Given an application with the following GenServers: `Session.Server`,
  `Logging.Server`, activate metrics-sampling for the server cluster as follows:

  ```elixir
  alias GenMetrics.GenServer.Cluster
  cluster = %Cluster{name: "demo",
                     servers: [Session.Server, Logging.Server],
                     opts: [sample_rate: 0.3]}
  GenMetrics.monitor_cluster(cluster)
  ```

  ### GenServer Summary Metrics

  Summary metrics are collected for activity within the following GenServer
  callbacks:

  - `GenServer.handle_call/3`
  - `GenServer.handle_cast/2`
  - `GenServer.handle_info/2`

  GenMetrics collects both the number of callbacks and the time taken on
  those callbacks for each of the server processes within your cluster.

  Summary metrics are aggregated across a periodic time interval, known as a
  *window*. By default, the window interval is `1000 ms`. This interval may be
  customized using the `window_interval` option on `GenMetrics.monitor_cluster/1`
  as shown here:

  ```
  alias GenMetrics.GenServer.Cluster
  cluster = %Cluster{name: "demo",
                     servers: [Session.Server, Logging.Server],
                     opts: [window_interval: 5000]}
  GenMetrics.monitor_cluster(cluster)
  ```

  The following are sample summary metrics reported for a single window interval
  on a GenServer process:

  ```
  # Server Name: Demo.Server, PID<0.176.0>

  %GenMetrics.GenServer.Summary{name: Demo.Server,
                                pid: #PID<0.176.0>,
                                calls: 8000,
                                casts: 34500,
                                infos: 3333,
                                time_on_calls: 28,
                                time_on_casts: 161,
                                time_on_infos: 15}
  ```

  All timings reported on summary metrics are reported in `milliseconds (ms)`.
  For example, during this sample window interval, the `handle_cast/2` callback
  was executed `34500` times. The total time spent processing those callbacks
  was just `161 ms`.

  ### GenServer Statistical Metrics

  Summary metrics provide near-realtime insights into the runtime behaviour
  of any GenServer application. However, sometimes more fine grained metrics
  data may be required to truly understand the subtleties of your application's
  runtime behaviour. To cater for those cases, GenMetrics supports optional
  statistical metrics.

  Statistical metrics may be activated using the `statistics` option on
  `GenMetrics.monitor_cluster/1`. GenMetrics `in-memory` metrics are activated
  as shown here:

  ```
  alias GenMetrics.GenServer.Cluster
  cluster = %Cluster{name: "demo",
                     servers: [Session.Server, Logging.Server],
                     opts: [statistics: true]}
  GenMetrics.monitor_cluster(cluster)
  ```

  Activating in-memory statistical metrics is a lot like activating a
  `statsd agent` directly within the BEAM. This can impact the runtime
  performance of some applications so redirecting metrics to an external
  agent is typically recommended.

  Redirecting statistical metrics to a `statsd` agent simply requires the
  following `opts` configuration:

  ```
  opts: [statistics: :statsd]}
  ```

  Redirecting statistical metrics to the `Datadog` statsd-agent requires the
  following `opts` configuration:

  ```
  opts: [statistics: :datadog]}
  ```

  Metrics directed to Datadog include tagging data which makes it very easy
  to subset and query the metrics that you need to monitor.

  The following are sample `in-memory` statistical metrics reported for a
  single window interval on a GenServer process:

  ```
  # Server Name: Demo.Server, PID<0.176.0>

  # handle_call/3
  %GenMetrics.GenServer.Stats{callbacks: 8000,
                              max: 149,
                              mean: 3,
                              min: 2,
                              range: 147,
                              stdev: 2,
                              total: 25753}

  # handle_cast/2
  %GenMetrics.GenServer.Stats{callbacks: 34500,
                              max: 3368,
                              mean: 4,
                              min: 2,
                              range: 3366,
                              stdev: 31,
                              total: 141383}

  # handle_info/2
  %GenMetrics.GenServer.Stats{callbacks: 3333,
                              max: 37,
                              mean: 4,
                              min: 2,
                              range: 35,
                              stdev: 2,
                              total: 13510}
  ```

  All timings reported on `in-memory` statistical metrics are reported in
  `microseconds (µs)`. For example, during this sample window interval, the
  `handle_cast/2` callback was executed `34500` times. The total time spent
  processing those callbacks was `141383 µs`. The `mean` time taken per
  callback was `4 µs` while the `standard deviation` around the mean was `31 µs`.

  *Note:* Under heavy load the generation of `in-memory` statistical metrics can
  become computationally expensive. It is therefore recommended that
  `in-memory` metrics be activated in production environments *judiciously*.
  These concerns are negligible when redirecting statistical metrics to
  `:statsd` or `:datadog` as custom sampling-rates may be configured.


  ### GenServer Reporting Metrics

  Runtime `in-memory` metrics for servers in your cluster are published via
  a dedicated reporting process. The reporting process is registered locally
  by the GenMetrics library at startup. This process is registered under the
  name `GenMetrics.GenServer.Reporter`.

  The reporting process is a `GenStage` producer that broadcasts metrics data.
  Any number of consumers can subscribe to this process in order to handle
  metrics data.

  Note, if you are redirecting statistical metrics to `:statsd` or `:datadog`
  there is no need to subscribe to this reporting process.

  In order to subscribe, a simple GenStage `:consumer` can initialize itself
  to receive events from the reporting process as follows:

  ```
  def init(:ok) do
    # Subscribe as consumer to the GenMetrics.GenServer.Reporter producer.
    {:consumer, :state_does_not_matter,
                subscribe_to: [{GenMetrics.GenServer.Reporter, max_demand: 1}]}
  end
  ```

  On receipt of events from the reporting process, metrics data can be extracted
  for processing to suit any need. The following example demonstrates simple
  logging of summary metrics data:

  ```
  def handle_events([metrics | _], _from, state) do
    # Log summary metrics for each server within the GenServer cluster.
    for summary <- metrics.summary do
      Logger.info "GenMetrics.Consumer: cluster.server summary=\#{inspect summary}"
    end
    {:noreply, [], state}
  end
  ```

  ## GenMetrics for GenStage Applications

  Any application using the `GenStage` behaviour can immediately benefit from
  the insights afforded by GenMetrics. The following sections explain how. For
  `GenServer` applications, see the docs
  [here](#module-genmetrics-for-genserver-applications).

  ### GenStage Metrics Activation

  A `GenMetrics.GenStage.Pipeline` struct is used to identify one or more
  GenStages that become candidates for metrics collection. You can
  identify a complete pipeline including all `:producers`, `:producer_consumers`
  and `:consumers`, or any subset of stages within a pipeline.

  For example, assuming your GenStage application has a `Data.Producer`,
  a `Data.Scrubber`, a `Data.Analyzer` and a `Data.Consumer`, you can activate
  metrics collection for the entire pipeline as follows:

  ```
  alias GenMetrics.GenStage.Pipeline
  pipeline = %Pipeline{name: "demo",
                       producer: [Data.Producer],
                       producer_consumer: [Data.Scrubber, Data.Analyzer],
                       consumer: [Data.Consumer]}
  GenMetrics.monitor_pipeline(pipeline)
  ```

  Alternatively, if you only wanted to activate metrics collection for the
  `:producer_consumer` stages within the pipeline you can do the following:

  ```
  alias GenMetrics.GenStage.Pipeline
  pipeline = %Pipeline{name: "demo", 
                       producer_consumer: [Data.Scrubber, Data.Analyzer]}
  GenMetrics.monitor_pipeline(pipeline)
  ```

  The *pipeline* in this context is simply a named set of one or more GenStage
  modules about which you would like to collect metrics data. Metrics data are
  collected on stage processes executing on the local node.

  GenMetrics will instantly attach to running GenStage processes associated
  with your pipeline. If there are no running GenStage processes associated with
  your pipleline when `GenMetrics.monitor_pipeline/1` is called, GenMetrics will
  monitor for process activation and automatically begin metrics collection
  for each new process.


  ### GenStage Metrics Sampling

  Sampling metrics is a effective way to collect and report metrics for
  any pipeline while minimizing the runtime overhead introduced by
  the GenMetrics monitoring agent.

  When sampling is disabled, metrics data reflect the exact behaviour of the
  processes being monitored. When sampling is enabled, metrics data reflect
  an approximation of the behaviour of the processes being monitored.

  Given a GenStage application with the following stages: `Data.Producer`,
  `Data.Scrubber`, `Data.Analyzer` and a `Data.Consumer`, activate
  metrics-sampling for the entire pipeline as follows:

  ```elixir
  alias GenMetrics.GenStage.Pipeline
  pipeline = %Pipeline{name: "demo",
                       producer: [Data.Producer],
                       producer_consumer: [Data.Scrubber, Data.Analyzer],
                       consumer: [Data.Consumer],
                       opts: [sample_rate: 0.1]}
  GenMetrics.monitor_pipeline(pipeline)
  ```

### GenMetrics Summary Metrics

  Summary metrics are collected for activity within the following GenStage
  callbacks:

  - `GenStage.handle_demand/2`
  - `GenStage.handle_events/3`
  - `GenStage.handle_call/3`
  - `GenStage.handle_cast/2`

  GenMetrics collects the number of callbacks, the time taken on those
  callbacks, the size of upstream demand, and the number of events generated
  in response to that demand, for each of the stages within your pipeline.

  Summary metrics are aggregated across a periodic time interval, known as a
  *window*. By default, the window interval is `1000 ms`. This interval may be
  customized using the `window_interval` option on
  `GenMetrics.monitor_pipeline/1` as shown here:

  ```
  alias GenMetrics.GenStage.Pipeline
  pipeline = %Pipeline{name: "demo",
                       producer_consumer: [Data.Scrubber, Data.Analyzer],
                       opts: [window_interval: 5000]}
  GenMetrics.monitor_pipeline(pipeline)
  ```

  The following are sample summary metrics reported for a single window interval
  on a GenStage process:

  ```
  # Stage Name: Data.Producer, PID<0.195.0>

  %GenMetrics.GenStage.Summary{stage: Data.Producer,
                               pid: #PID<0.195.0>,
                               callbacks: 9536,
                               time_on_callbacks: 407,
                               demand: 4768000,
                               events: 4768000}
  ```

  All timings reported on summary metrics are reported in `milliseconds (ms)`.
  For example, during this sample window interval, `9536` callbacks were
  handled by the `Data.Producer` stage. The total time spent processing those
  callbacks was `407 ms`.

  During that time, total upstream demand on the stage was `4768000`. A total of
  `4768000` events were also generated and emitted by the stage. This tells us
  that the stage was able to fully meet upstream demand during this specific
  sample window interval.

  ### GenMetrics Statistical Metrics

  Summary metrics provide near-realtime insights into the runtime behaviour
  of any GenStage application. However, sometimes more fine grained metrics
  data may be required to truly understand the subtleties of your application's
  runtime behaviour. To cater for those cases, GenMetrics supports optional
  statistical metrics.

  Statistical metrics may be activated using the `statistics` option on
  `GenMetrics.monitor_pipeline/1`. GenMetrics `in-memory` metrics are activated
  as shown here:

  ```
  alias GenMetrics.GenStage.Pipeline
  pipeline = %Pipeline{name: "demo",
                       producer_consumer: [Data.Scrubber, Data.Analyzer],
                       opts: [statistics: true]}
  GenMetrics.monitor_pipeline(pipeline)
  ```

  Redirecting statistical metrics to a `statsd` agent simply requires the
  following `opts` configuration:

  ```
  opts: [statistics: :statsd]}
  ```

  Redirecting statistical metrics to the `Datadog` statsd-agent requires the
  following `opts` configuration:

  ```
  opts: [statistics: :datadog]}
  ```

  Metrics directed to Datadog include tagging data which makes it very easy
  to subset and query the metrics that you need to monitor.

  The following are sample `in-memory` statistical metrics reported for a
  single window interval on a GenStage process:

  ```
  # Stage Name: Data.Producer, PID<0.195.0>

  # callback demand
  %GenMetrics.GenStage.Stats{callbacks: 9536,
                             max: 500,
                             mean: 500,
                             min: 500,
                             range: 0,
                             stdev: 0,
                             total: 4768000}
  # callback events
  %GenMetrics.GenStage.Stats{callbacks: 9536,
                             max: 500,
                             mean: 500,
                             min: 500,
                             range: 0,
                             stdev: 0,
                             total: 4768000}

  # callback timings
  %GenMetrics.GenStage.Stats{callbacks: 9536,
                             max: 2979,
                             mean: 42,
                             min: 24,
                             range: 2955,
                             stdev: 38,
                             total: 403170}
  ```

  All timings reported on `in-memory` statistical metrics are reported in
  `microseconds (µs)`. For example, during this sample window interval, `9536`
  callbacks were handled by the `Data.Producer` stage. The total time spent
  processing those callbacks was `403170 µs`. The `mean` time taken per
  callback was `42 µs` while the `standard deviation` around the mean was
  `38 µs`.

  Here, the total upstream demand of `4768000` equalled the total events emitted
  by the stage. This tells us that the stage was able to fully meet upstream
  demand during this specific sample window interval.

  *Note:* Under heavy load the generation of `in-memory` statistical metrics can
  become computationally expensive. It is therefore recommended that
  `in-memory` metrics be activated in production environments *judiciously*.
  These concerns are negligible when redirecting statistical metrics to
  `:statsd` or `:datadog` as custom sampling-rates may be configured.

  ### GenMetrics Reporting Metrics

  Runtime `in-memory` metrics for stages in your pipeline are published
  via a dedicated reporting process. The reporting process is registered
  locally by the GenMetrics library at startup. This process is registered
  under the name `GenMetrics.GenStage.Reporter`.

  The reporting process itself is a `GenStage` producer that broadcasts metrics
  data. Any number of consumers can subscribe to this process in order to handle
  metrics data.

  Note, if you are redirecting statistical metrics to `:statsd` or `:datadog`
  there is no need to subscribe to this reporting process.

  In order to subscribe, a simple GenStage `:consumer` can initialize itself
  to receive events from the reporting process as follows:

  ```
  def init(:ok) do
    # Subscribe as consumer to the GenMetrics.GenStage.Reporter producer.
    {:consumer, :state_does_not_matter,
                subscribe_to: [{GenMetrics.GenStage.Reporter, max_demand: 1}]}
  end
  ```

  On receipt of events from the reporting process, metrics data can be extracted
  for processing to suit any need. The following example demonstrates simple
  logging of summary metrics data:

  ```
  def handle_events([metrics | _], _from, state) do
    # Log summary metrics for each stage within the GenStage pipeline.
    for summary <- metrics.summary do
      Logger.info "GenMetrics.Consumer: pipeline.stage summary=\#{inspect summary}"
    end
    {:noreply, [], state}
  end
  ```

  """

  alias GenMetrics.GenServer
  alias GenMetrics.GenStage
  alias GenMetrics.GenServer.Cluster
  alias GenMetrics.GenStage.Pipeline

  @doc """
  Activate metrics collection and publishing for one or more GenServers.

  ## Example Usage

  Assuming an application has a `Session.Server` and a `Logging.Server` you
  can activate metrics collection on both GenServers as follows:

  ```
  alias GenMetrics.GenServer.Cluster
  cluster = %Cluster{name: "demo",
                     servers: [Session.Server, Logging.Server],
                     opts: [window_interval: 5000]}
  GenMetrics.monitor_cluster(cluster)
  ```

  ## Cluster Validation

  When this function is called the GenMetrics library checks and verifies
  the following conditions are met:

  1. All server modules specified on the cluster can be located and loaded
  1. All server modules specified on the cluster implement the GenServer
  behaviour

  If any module in the cluster does not meet these conditions the
  function terminates with a `:bad_cluster` response and supporting error
  messages.

  ## Metrics Reporting

  By default, metrics data gathered on your cluster are maintained `in-memory`
  and reported by a dedicated reporting process. However, metrics data can
  be redirected to `:statsd` or `:datadog` using the `statistics` configuration
  option on this call.

  For example: redirect your cluster metrics data to the `Datadog` service as
  follows:

  ```
  alias GenMetrics.GenServer.Cluster
  cluster = %Cluster{name: "demo",
                     servers: [Session.Server, Logging.Server],
                     opts: [statistics: :datadog]}
  GenMetrics.monitor_cluster(cluster)
  ```

  """
  @spec monitor_cluster(%Cluster{}) ::
  {:ok, pid} | {:error, :bad_server, [String.t]}
  def monitor_cluster(%Cluster{} = cluster) do
    Supervisor.start_child(GenServer.Supervisor, [cluster])
  end

  @doc """
  Activate metrics collection and publishing for one or more stages
  within a GenStage pipeline.

  ## Example Usage

  Assuming a GenStage application has a `Data.Producer`, a `Data.Scrubber`,
  a `Data.Analyzer` and a `Data.Consumer`, you can activate metrics
  collection for the entire pipeline as follows:

  ```
  alias GenMetrics.GenStage.Pipeline
  pipeline = %Pipeline{name: "demo",
                       producer: [Data.Producer],
                       producer_consumer: [Data.Scrubber, Data.Analyzer],
                       consumer: [Data.Consumer]}
  GenMetrics.monitor_pipeline(pipeline)
  ```

  ## Pipeline Validation

  When this function is called the GenMetrics library checks and verifies
  the following conditions are met:

  1. All stage modules specified on the pipeline can be located and loaded
  1. All stage modules specified on the pipeline implement the GenStage behaviour

  If any module in the pipeline does not meet these conditions the
  function terminates with a `:bad_pipeline` response and supporting error
  messages.


  ## Metrics Reporting

  By default, metrics data gathered on your pipeline are maintained `in-memory`
  and reported by a dedicated reporting process. However, metrics data can
  be redirected to `:statsd` or `:datadog` using the `statistics` configuration
  option on this call.

  For example: redirect your pipeline metrics data to a `statsd` agent as
  follows:

  ```
  alias GenMetrics.GenStage.Pipeline
  pipeline = %Pipeline{name: "demo",
                       producer: [Data.Producer],
                       producer_consumer: [Data.Scrubber, Data.Analyzer],
                       consumer: [Data.Consumer],
                       opts: [statistics: :statsd]}
  GenMetrics.monitor_pipeline(pipeline)
  ```
  """
  @spec monitor_pipeline(%Pipeline{}) ::
  {:ok, pid} | {:error, :bad_pipeline, [String.t]}
  def monitor_pipeline(%Pipeline{} = pipeline) do
    Supervisor.start_child(GenStage.Supervisor, [pipeline])
  end

end
