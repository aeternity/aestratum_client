-module(aestratum_client).

-export([status/0]).

-spec status() -> map().
status() ->
    aestratum_client_handler:status().

