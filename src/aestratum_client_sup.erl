-module(aestratum_client_sup).

-behaviour(supervisor).

%% API.
-export([start_link/1]).

%% supervisor callbacks.
-export([init/1]).

-type config() :: aestratum_client_config:config().

-define(SERVER, ?MODULE).

%% API.

-spec start_link(config()) -> {ok, pid()}.
start_link(Cfg) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, Cfg).

%% supervisor callbacks.

init(Cfg) ->
    Procs =
        [{aestratum_client_handler,
          {aestratum_client_handler, start_link, [Cfg]},
          permanent, 5000, worker, [aestratum_client_handler]},
         {aestratum_client_generator_sup,
          {aestratum_client_generator_sup, start_link, [Cfg]},
          permanent, 5000, supervisor, [aestratum_client_generator_sup]}],
    {ok, {{one_for_one, 1, 5}, Procs}}.

