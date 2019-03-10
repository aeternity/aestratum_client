-module(aestratum_client_sup).

-behaviour(supervisor).

%% API.
-export([start_link/1]).

%% supervisor callbacks.
-export([init/1]).

-define(SERVER, ?MODULE).

%% API.

start_link(Opts) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, Opts).

%% supervisor callbacks.

init(Opts) ->
    Procs =
        [{aestratum_client_handler,
          {aestratum_client_handler, start_link, [Opts]},
          permanent, 5000, worker, [aestratum_client_handler]},
         {aestratum_client_generator_sup,
          {aestratum_client_generator_sup, start_link, [Opts]},
          permanent, 5000, supervisor, [aestratum_client_generator_sup]}],
    {ok, {{one_for_one, 1, 5}, Procs}}.

