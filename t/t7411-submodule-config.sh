#!/bin/sh
#
# Copyright (c) 2014 Heiko Voigt
#

test_description='Test submodules config cache infrastructure

This test verifies that parsing .gitmodules configurations directly
from the database and from the worktree works.
'

TEST_NO_CREATE_REPO=1
. ./test-lib.sh

test_expect_success 'submodule config cache setup' '
	mkdir submodule &&
	(cd submodule &&
		git init &&
		echo a >a &&
		git add . &&
		git commit -ma
	) &&
	mkdir super &&
	(cd super &&
		git init &&
		git submodule add ../submodule &&
		git submodule add ../submodule a &&
		git commit -m "add as submodule and as a" &&
		git mv a b &&
		git commit -m "move a to b"
	)
'

test_expect_success 'configuration parsing with error' '
	test_when_finished "rm -rf repo" &&
	test_create_repo repo &&
	cat >repo/.gitmodules <<-\EOF &&
	[submodule "s"]
		path
		ignore
	EOF
	(
		cd repo &&
		test_must_fail test-tool submodule-config "" s 2>actual &&
		test_i18ngrep "bad config" actual
	)
'

cat >super/expect <<EOF
Submodule name: 'a' for path 'a'
Submodule name: 'a' for path 'b'
Submodule name: 'submodule' for path 'submodule'
Submodule name: 'submodule' for path 'submodule'
EOF

test_expect_success 'test parsing and lookup of submodule config by path' '
	(cd super &&
		test-tool submodule-config \
			HEAD^ a \
			HEAD b \
			HEAD^ submodule \
			HEAD submodule \
				>actual &&
		test_cmp expect actual
	)
'

test_expect_success 'test parsing and lookup of submodule config by name' '
	(cd super &&
		test-tool submodule-config --name \
			HEAD^ a \
			HEAD a \
			HEAD^ submodule \
			HEAD submodule \
				>actual &&
		test_cmp expect actual
	)
'

cat >super/expect_error <<EOF
Submodule name: 'a' for path 'b'
Submodule name: 'submodule' for path 'submodule'
EOF

test_expect_success 'error in one submodule config lets continue' '
	(cd super &&
		cp .gitmodules .gitmodules.bak &&
		echo "	value = \"" >>.gitmodules &&
		git add .gitmodules &&
		mv .gitmodules.bak .gitmodules &&
		git commit -m "add error" &&
		test-tool submodule-config \
			HEAD b \
			HEAD submodule \
				>actual &&
		test_cmp expect_error actual
	)
'

test_expect_success 'error message contains blob reference' '
	# Remove the error introduced in the previous test.
	# It is not needed in the following tests.
	test_when_finished "git -C super reset --hard HEAD^" &&
	(cd super &&
		sha1=$(git rev-parse HEAD) &&
		test-tool submodule-config \
			HEAD b \
			HEAD submodule \
				2>actual_err &&
		test_i18ngrep "submodule-blob $sha1:.gitmodules" actual_err >/dev/null
	)
'

test_expect_success 'using different treeishs works' '
	(
		cd super &&
		git tag new_tag &&
		tree=$(git rev-parse HEAD^{tree}) &&
		commit=$(git rev-parse HEAD^{commit}) &&
		test-tool submodule-config $commit b >expect &&
		test-tool submodule-config $tree b >actual.1 &&
		test-tool submodule-config new_tag b >actual.2 &&
		test_cmp expect actual.1 &&
		test_cmp expect actual.2
	)
'

test_expect_success 'error in history in fetchrecursesubmodule lets continue' '
	test_when_finished "git -C super reset --hard HEAD^" &&
	(cd super &&
		git config -f .gitmodules \
			submodule.submodule.fetchrecursesubmodules blabla &&
		git add .gitmodules &&
		git config --unset -f .gitmodules \
			submodule.submodule.fetchrecursesubmodules &&
		git commit -m "add error in fetchrecursesubmodules" &&
		test-tool submodule-config \
			HEAD b \
			HEAD submodule \
				>actual &&
		test_cmp expect_error actual
	)
'

test_expect_success 'reading submodules config with "submodule--helper config"' '
	(cd super &&
		echo "../submodule" >expected &&
		git submodule--helper config submodule.submodule.url >actual &&
		test_cmp expected actual
	)
'

test_expect_success 'writing submodules config with "submodule--helper config"' '
	(cd super &&
		echo "new_url" >expected &&
		git submodule--helper config submodule.submodule.url "new_url" &&
		git submodule--helper config submodule.submodule.url >actual &&
		test_cmp expected actual
	)
'

test_expect_success 'overwriting unstaged submodules config with "submodule--helper config"' '
	(cd super &&
		echo "newer_url" >expected &&
		git submodule--helper config submodule.submodule.url "newer_url" &&
		git submodule--helper config submodule.submodule.url >actual &&
		test_cmp expected actual
	)
'

test_done
