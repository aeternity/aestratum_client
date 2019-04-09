REBAR = ./rebar3

.PHONY: all dialyzer ct eunit clean distclean console

EUNIT_TEST_FLAGS ?=

ifdef TEST
EUNIT_TEST_FLAGS += --module=$(TEST)
unexport TEST
endif

all:
	$(REBAR) as local compile

doc:
	$(REBAR) as local doc

dialyzer:
	$(REBAR) as local dialyzer

ct:
	$(REBAR) as test ct

eunit:
	$(REBAR) as test eunit $(EUNIT_TEST_FLAGS)

rel:
	$(REBAR) as prod release

clean:
	$(REBAR) clean
	rm -rf doc/*

distclean: clean
	rm -rf _build

console:
	$(REBAR) as local shell

