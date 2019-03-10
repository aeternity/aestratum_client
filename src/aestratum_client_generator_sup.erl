-module(aestratum_client_generator_sup).

-behaviour(supervisor).

%% API.
-export([start_link/1]).

%% supervisor callbacks.
-export([init/1]).

%% API.

start_link(Opts) ->
    supervisor:start_link(?MODULE, Opts).

%% supervisor callback.

init(Opts) ->
    Procs =
        [{aestratum_client_generator_manager,
          {aestratum_client_generator_manager, start_link, [Opts]},
          permanent, 5000, worker, [aestratum_client_generator_manager]},
         {aestratum_client_generator_worker_sup,
          {aestratum_client_generator_worker_sup, start_link, [Opts]},
          permanent, 5000, supervisor, [aestratum_client_generator_worker_sup]}],
    {ok, {{one_for_all, 1, 5}, Procs}}.

