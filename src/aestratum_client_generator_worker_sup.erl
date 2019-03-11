-module(aestratum_client_generator_worker_sup).

-behaviour(supervisor).

%% API.
-export([start_link/1]).

%% supervisor callbacks.
-export([init/1]).

-type config() :: aestratum_client_config:config().

%% API.

-spec start_link(config()) -> {ok, pid()}.
start_link(Config) ->
    supervisor:start_link(?MODULE, Config).

%% supervisor callbacks.

init(#{miners := MinerConfigs}) ->
    Miners = configs_to_miners(MinerConfigs),
    Procs =
        [{{aestratum_client_generator_worker, aestratum_client_miner:id(Miner)},
          {aestratum_client_generator_worker, start_link, [Miner]},
          permanent, brutal_kill, worker, [aestratum_client_generator_worker]}
         || Miner <- Miners],
    {ok, {{one_for_one, 1, 5}, Procs}}.

%% Converts the client's configs into miner configs and they are converted
%% into miners.
configs_to_miners(MinerConfigs) ->
    configs_to_miners([to_miner_config(MinerConfig)
                       || MinerConfig <- MinerConfigs], 0, []).

configs_to_miners([MinerConfig | MinerConfigs], Id, Acc) ->
    case aestratum_miner:instances(MinerConfig) of
        undefined ->
            {Id1, Acc1} = add_miners(Id, [undefined], MinerConfig, Acc),
            configs_to_miners(MinerConfigs, Id1, Acc1);
        Instances when is_list(Instances) ->
            {Id1, Acc1} = add_miners(Id, Instances, MinerConfig, Acc),
            configs_to_miners(MinerConfigs, Id1, Acc1)
    end;
configs_to_miners([], _Id, Acc) ->
    lists:reverse(Acc).

add_miners(Id, [Instance | Instances], MinerConfig, Acc) ->
    Acc1 = [aestratum_client_miner:new(Id, Instance, MinerConfig) | Acc],
    add_miners(Id + 1, Instances, MinerConfig, Acc1);
add_miners(Id, [], _MinerConfig, Acc) ->
    {Id, Acc}.

to_miner_config(#{exec := Exec, exec_group := ExecGroup, extra_args := ExtraArgs,
                  hex_enc_hdr := HexEncHdr, repeats := Repeats,
                  edge_bits := EdgeBits, instances := Instances}) ->
    aestratum_miner:config(Exec, ExecGroup, ExtraArgs, HexEncHdr, Repeats,
                           EdgeBits, Instances).

