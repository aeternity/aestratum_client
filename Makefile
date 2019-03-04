REBAR = ./rebar3

.PHONY: all dialyzer ct eunit clean distclean console

EUNIT_TEST_FLAGS ?=

ifdef TEST
EUNIT_TEST_FLAGS += --module=$(TEST)
unexport TEST
endif

all:
	$(REBAR) compile

doc:
	$(REBAR) doc

dialyzer:
	$(REBAR) dialyzer

ct:
	$(REBAR) ct

eunit:
	$(REBAR) eunit $(EUNIT_TEST_FLAGS)


clean:
	$(REBAR) clean
	rm -rf doc/*

distclean: clean
	rm -rf _build

console:
	$(REBAR) shell

