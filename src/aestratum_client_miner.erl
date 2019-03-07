-module(aestratum_client_miner).

-export([new/3,
         id/1,
         instance/1,
         config/1
        ]).

-export_type([id/0,
              miner/0
             ]).

-type id()         :: non_neg_integer().

-type instance()   :: aestratum_miner:instance().

-type config()     :: aestratum_miner:config().

-record(miner, {
          id       :: id(),
          instance :: instance(),
          config   :: config()
         }).

-opaque miner()    :: #miner{}.

-spec new(id(), instance(), config()) -> miner().
new(Id, Instance, Config) ->
    #miner{id = Id, instance = Instance, config = Config}.

-spec id(miner()) -> id().
id(#miner{id = Id}) ->
    Id.

-spec instance(miner()) -> instance().
instance(#miner{instance = Instance}) ->
    Instance.

-spec config(miner()) -> config().
config(#miner{config = Config}) ->
    Config.

