#!/usr/bin/env perl

use warnings;
use strict;
use Test::More;

BEGIN {
    use lib('t');
    require TestUtils;
    import TestUtils;
    use FindBin;
    use lib "$FindBin::Bin/lib/lib/perl5";
}

plan( tests => 78 );

##################################################
# create our test site
my $omd_bin = TestUtils::get_omd_bin();
my $site    = TestUtils::create_test_site() or TestUtils::bail_out_clean("no further testing without site");
print `mv /omd/sites/$site/etc/apache/conf.d/disable_nagios.off /omd/sites/$site/etc/apache/conf.d/disable_nagios.conf`;

# not started site should give a nice error
TestUtils::test_command({ cmd => "/bin/su - $site -c 'lib/nagios/plugins/check_http -H localhost -u /$site -e 503 -r \"OMD: Site Not Started\"'",  like => '/HTTP OK:/' });

##################################################
# execute some checks
my $tests = [
  { cmd => $omd_bin." start $site" },

  { cmd => "/bin/su - $site -c 'lib/nagios/plugins/check_http -H localhost -u /$site -e 302'",                      like => '/HTTP OK:/' },
  { cmd => "/bin/su - $site -c 'lib/nagios/plugins/check_http -H localhost -u /$site/ -e 302'",                     like => '/HTTP OK:/' },
  { cmd => "/bin/su - $site -c 'lib/nagios/plugins/check_http -H localhost -u /$site/omd -e 401'",                  like => '/HTTP OK:/' },
  { cmd => "/bin/su - $site -c 'lib/nagios/plugins/check_http -H localhost -a omdadmin:omd -u /$site -e 302'",      like => '/HTTP OK:/' },
  { cmd => "/bin/su - $site -c 'lib/nagios/plugins/check_http -H localhost -a omdadmin:omd -u /$site/omd -e 301'",  like => '/HTTP OK:/' },
  { cmd => "/bin/su - $site -c 'lib/nagios/plugins/check_http -H localhost -a omdadmin:omd -u /$site/omd/ -e 302'", like => '/HTTP OK:/' },

  { cmd => $omd_bin." stop $site" },
];
for my $test (@{$tests}) {
    TestUtils::test_command($test);
}

TestUtils::test_command({ cmd => "/bin/su - $site -c 'omd config set APACHE_MODE ssl'",  like => '/^$/' });
TestUtils::restart_system_apache();
TestUtils::test_command({ cmd => "/bin/su - $site -c 'omd start'",  like => '/Starting dedicated Apache.*?OK/' });
TestUtils::test_command({ cmd => "/bin/su - $site -c 'lib/nagios/plugins/check_http -H localhost -S -a omdadmin:omd -u /$site/thruk/startup.html -e 200 -vvv'", like => ['/HTTP OK:/', '/Please stand by, Thruks FastCGI Daemon is warming/'] });

# omd diff should list no files after creating a site, otherwise hooks are wrong and create lots of conflicts on every update
{
    my $test = { cmd => $omd_bin." diff $site",     unlike => '/Changed content/', like => '/^$/' };
    TestUtils::test_command($test);
    my @failed = $test->{'stdout'} =~ m|^\s*\*\s+Changed\s+content\s+(.*)$|gmx;
    for my $file (@failed) {
        diag($file);
        my $test = { cmd => $omd_bin." diff $site $file" };
        TestUtils::test_command($test);
        diag($test->{'stdout'});
    }
}

##################################################
# test if nagios cgis are no longer in place
TestUtils::test_command({ cmd => "/bin/su - $site -c 'lib/nagios/plugins/check_http -H localhost -S -a omdadmin:omd -u /$site/nagios/ -e 403 -vvv'", like => ['/HTTP OK:/', '/OMD: Disabled/'] });
TestUtils::test_command({ cmd => "/bin/su - $site -c 'lib/nagios/plugins/check_http -H localhost -S -a omdadmin:omd -u /$site/nagios/images/logos/debian.png -e 200 -v'", like => ['/HTTP OK:/', '/png/'] });

##################################################
TestUtils::test_command({ cmd => "/bin/su - $site -c 'omd stop'",  like => '/Stopping dedicated Apache/' });

##################################################
# cleanup test site
TestUtils::remove_test_site($site);
