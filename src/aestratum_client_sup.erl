-module(aestratum_client_sup).

-behaviour(supervisor).

-export([start_link/1,
         init/1
        ]).

-define(SERVER, ?MODULE).

start_link(Opts) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, [Opts]).

init([Opts]) ->
    Procs = [handler(Opts)],
    {ok, {{one_for_one, 5, 10}, Procs}}.

handler(Opts) ->
    {aestratum_client_handler,
     {aestratum_client_handler, start_link, [Opts]},
      permanent, 5000, worker, [aestratum_client_handler]}.

