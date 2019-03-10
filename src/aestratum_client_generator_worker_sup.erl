-module(aestratum_client_generator_worker_sup).

-behaviour(supervisor).

%% API.
-export([start_link/1]).

%% supervisor callbacks.
-export([init/1]).

-type config() :: aestratum_miner:config().

%% API.

-spec start_link([config()]) -> {ok, pid()}.
start_link(Opts) ->
    supervisor:start_link(?MODULE, Opts).

%% supervisor callbacks.

init(#{miner_configs := Configs}) ->
    Miners = configs_to_miners(Configs),
    Procs =
        [{{aestratum_client_generator_worker, aestratum_client_miner:id(Miner)},
          {aestratum_client_generator_worker, start_link, [Miner]},
          permanent, brutal_kill, worker, [aestratum_client_generator_worker]}
         || Miner <- Miners],
    {ok, {{one_for_one, 1, 5}, Procs}}.

configs_to_miners(Configs) ->
    configs_to_miners(Configs, 0, []).

configs_to_miners([Config | Configs], Id, Acc) ->
    case aestratum_miner:instances(Config) of
        undefined ->
            {Id1, Acc1} = add_miners(Id, [undefined], Config, Acc),
            configs_to_miners(Configs, Id1, Acc1);
        Instances when is_list(Instances) ->
            {Id1, Acc1} = add_miners(Id, Instances, Config, Acc),
            configs_to_miners(Configs, Id1, Acc1)
    end;
configs_to_miners([], _Id, Acc) ->
    lists:reverse(Acc).

add_miners(Id, [Instance | Instances], Config, Acc) ->
    Acc1 = [aestratum_client_miner:new(Id, Instance, Config) | Acc],
    add_miners(Id + 1, Instances, Config, Acc1);
add_miners(Id, [], _Config, Acc) ->
    {Id, Acc}.

