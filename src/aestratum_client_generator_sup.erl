-module(aestratum_client_generator_sup).

-behaviour(supervisor).

%% API.
-export([start_link/1]).

%% supervisor callbacks.
-export([init/1]).

-type config() :: aestratum_client_config:config().

%% API.

-spec start_link(config()) -> {ok, pid()}.
start_link(Cfg) ->
    supervisor:start_link(?MODULE, Cfg).

%% supervisor callback.

init(Cfg) ->
    Procs =
        [{aestratum_client_generator_manager,
          {aestratum_client_generator_manager, start_link, []},
          permanent, 5000, worker, [aestratum_client_generator_manager]},
         {aestratum_client_generator_worker_sup,
          {aestratum_client_generator_worker_sup, start_link, [Cfg]},
          permanent, 5000, supervisor, [aestratum_client_generator_worker_sup]}],
    {ok, {{one_for_all, 1, 5}, Procs}}.

