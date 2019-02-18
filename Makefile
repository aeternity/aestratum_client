REBAR = ./rebar3

.PHONY: all dialyzer ct eunit clean distclean console

all:
	$(REBAR) compile

doc:
	$(REBAR) doc

dialyzer:
	$(REBAR) dialyzer

ct:
	$(REBAR) ct

eunit:
	$(REBAR) eunit --module=aestratum_client_session_tests

clean:
	$(REBAR) clean
	rm -rf doc/*

distclean: clean
	rm -rf _build

console:
	$(REBAR) shell

