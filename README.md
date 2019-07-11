Aeternity stratum client (alpha)
==========

Introduction
==========

The client side implementation of the Stratum protocol customized for Aeternity [https://github.com/aeternity/protocol/blob/master/STRATUM.md] lives in Aestratum client repository.

The dependency tree of Aestratum client shows how the actual mining executable fits in:

```
aestratum_client
|- aestratum_lib
   |- aeminer
      |- aecuckooprebuilt (for CUDA)  # executable in repository
      |- aecuckoo         (for CPU)   # executable built via compilation
```

Aecuckoo (for CPU and CUDA) are executables implementing the Cuckoo Cycle algorithm used in Aeternity network, whose output artefacts (nonce and proof) are used for constructing of the blocks.

A Cyckoo Cycle is a memory hard algorithm, looking for a cycle (of length 42) in graph with `miners > edge_bits` edges.

Aestratum client roughly operates in the following manner:

1.) receives `extra nonce` after connecting to the server, of byte size = EB (in range 1..7 (inclusive))
2.) for each new job, randomly chooses a `miner nonce` (in the range = 2^(8 - EB))
3.) concatenates `miner nonce` and `extra nonce` to form an 8 bytes long number - `nonce`
4.) generates a graph from `nonce` (with edges count =  2^(`miners > edge_bits`))
5.) tries to find a cycle (of 42 nodes) in the graph
6.) if no such cycle is found, increases `nonce` by one and goes to 4.) `miners > repeats` times

If, in the step 5.) we find a cycle, we have found a nonce generating a graph, which also has a cycle in it (in a form of a list of 42 numbers, where each number represents a node).

The `miner nonce` and the `proof of work` (the cycle) are sent back to Aestratum server as a reply to the job request.
As a consequence, Aestratum server assigns a share to this client, whose value correlates with the difficulty of the delivered solution.
This share is then persisted, and potentially rewarded.

In Aeternity main net, we use `miners > edge_bits` set to 29, as the graph with 2^29 edges fits in CUDA graphics cards with 8 GB of memory.


Better insight when and how is a share rewarded can be found in the stratum server user guide. [https://github.com/aeternity/aeternity/blob/master/docs/stratum.md]


Configuration
==========

Current Aestratum client should be understood as alpha version with several ineffectual configuration parameters.

Example configuration section in your aestratum_client.yml configuration file could look as follows:

```
connection:
        transport: tcp
        host: "localhost"
        port: 9999
user:
        account: "ak_your_account_address_here"
        worker: "worker1"
miners:
        - exec: "mean29-generic"
          exec_group: "aecuckoo"
          extra_args: ""
          hex_enc_hdr: false
          repeats: 100
          edge_bits: 29
```


CONNECTION section
==========

`host` - a Stratum server host where the client wants to connect to

`port` - (optional) - a port of the Stratum server client wants to connect to
(default 9999)

`transport` - (optional) - mode of transport of data - SSL needs to be tested
(default TCP)

`req_timeout` - (optional) - request timeout in seconds
(default 15)

`req_retries` - (optional) - how many times to retry a request in case of failure
(default 3)


USER section
==========

`account` - account of the miner where to receive rewards from submitting shares

`worker` - name of the worker grouping miner executables mining under the same connection to server
(this configuration parameter will be needed when we implement client proxy)
(default "worker1")


MINERS section
==========

`miners` key is represented by array elements each potentially describing a different miner executable. Currently, there's exactly one miner configuration allowed.

Properties of each miner are:

`exec` - name of the executable binary spawned to solve a particular instance of the Cuckoo Cycle problem

`exec_group` - (optional) - where to look for the solver binary. If "aecuckoo", uses solver binary from `aecuckoo` dependency [https://github.com/aeternity/aecuckoo], in case of `aecuckooprebuilt`, we look into `aeminer/priv/aecuckooprebuilt/` directory.
(default "aecuckoo")

`extra_args` - (optional) - extra arguments passed to the miner executable
(default "")

`hex_enc_hdr` - (optional) - whether we hex encode the header passed as argument to the miner executable or not. For compatibility with Aestratum server, we need to set this configuration parameter to `false`.
(default true)

`repeats` - (optional) - how many solutions to try in a sequence from starting nonce.
(default 20)

`edge_bits` - (optional) - how many edges are in the graph generated from a nonce.
(default 29)



BUILDING of a Aestratum client
==========

In a cloned directory from the repository, run: `make`

STARTING of Aestratum client
==========

Run: `make shell`
