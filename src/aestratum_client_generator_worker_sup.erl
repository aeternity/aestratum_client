-module(aestratum_client_generator_worker_sup).

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

%% supervisor callbacks.

init(#{miners_cfg := MinerCfgs}) ->
    Miners = configs_to_miners(MinerCfgs),
    Procs =
        [{{aestratum_client_generator_worker, aestratum_client_miner:id(Miner)},
          {aestratum_client_generator_worker, start_link, [Miner]},
          permanent, 5000, worker, [aestratum_client_generator_worker]}
         || Miner <- Miners],
    {ok, {{one_for_one, 1, 5}, Procs}}.

%% Converts the client's configs into miner configs and they are converted
%% into miners.
configs_to_miners(MinerCfgs) ->
    configs_to_miners([to_miner_config(MinerCfg)
                       || MinerCfg <- MinerCfgs], 0, []).

configs_to_miners([MinerCfg | MinerCfgs], Id, Acc) ->
    case aestratum_miner:instances(MinerCfg) of
        undefined ->
            {Id1, Acc1} = add_miners(Id, [undefined], MinerCfg, Acc),
            configs_to_miners(MinerCfgs, Id1, Acc1);
        Instances when is_list(Instances) ->
            {Id1, Acc1} = add_miners(Id, Instances, MinerCfg, Acc),
            configs_to_miners(MinerCfgs, Id1, Acc1)
    end;
configs_to_miners([], _Id, Acc) ->
    lists:reverse(Acc).

add_miners(Id, [Instance | Instances], MinerCfg, Acc) ->
    Acc1 = [aestratum_client_miner:new(Id, Instance, MinerCfg) | Acc],
    add_miners(Id + 1, Instances, MinerCfg, Acc1);
add_miners(Id, [], _MinerCfg, Acc) ->
    {Id, Acc}.

to_miner_config(#{exec := Exec, exec_group := ExecGroup, extra_args := ExtraArgs,
                  hex_enc_hdr := HexEncHdr, repeats := Repeats,
                  edge_bits := EdgeBits, instances := Instances}) ->
    aestratum_miner:config(Exec, ExecGroup, ExtraArgs, HexEncHdr, Repeats,
                           EdgeBits, Instances).

