# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Config;

use strict;

use Taranis      qw(:all);
use XML::Simple;
use Carp         qw(confess);
use Scalar::Util qw(reftype);

# overwritten in TestUtil
our $mainconfig;
my $xs;

BEGIN {
	$mainconfig = ($ENV{TARANIS_HOME} || $ENV{HOME}) . '/etc/taranis.conf.xml';
}

sub new(;$) {
	my ($class, $config_relfn) = @_;
	$config_relfn ||= $mainconfig;
	my $config_fn = find_config $config_relfn
		or die "ERROR: cannot find config file $config_relfn\n";

	$xs ||= XML::Simple->new(NormaliseSpace => 2, SuppressEmpty => '');
	my @xml = $xs->XMLin($config_fn);
	my $cfglayout = $xml[0];

	$cfglayout->{__filename} = $config_fn
		if ref $cfglayout eq 'HASH';

	bless $cfglayout, $class;
}

sub filename() {
	my $self = shift;
	reftype $self eq 'HASH' ? $self->{__filename} : undef;
}

sub getSetting {
	my ($thing, $want) = @_;
	my $self = ref $thing ? $thing : $thing->new;
	$self->{$want};
}

sub saveSettings {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};

	my $file = delete $settings{file};

	eval{
		my $fh;
		open( $fh, ">", $file) or $self->{errmsg} = "open($file): $!";
		XMLout( \%settings, NoAttr => 1, RootName => 'settings', OutputFile => $fh, XMLDecl => 1 );
		close $fh;
	};
	
	if ($@) {
		$self->{errmsg} = $@;
		return 0;
	} else {
		return 1;
	}
}

sub publicationTemplateName($$) {
	my ($self, $group, $which) = @_;

	my $pubs = $self->{_pubtempls};
	unless($pubs) {
		my $fn = $self->{publication_templates} or confess;
		$pubs = $self->{_pubtempls} = __PACKAGE__->new($fn);
	}

	$pubs->{$group}{$which};
}

sub isEnabled($) {
	my ($self, $flag) = @_;
	my $val = $self->{$flag};

	# Explicit '0' for backward compatibility
	defined $val && lc($val) eq 'on' ? 1 : 0;
}

sub publishWebsite() {
	my $config = shift->{publish_website} || {};
	$config->{implementation} =~ /\S/ ? $config : undef;
}

=head1 NAME 

Taranis::Config - Module for retrieving configuration settings from XML files.

=head1 SYNOPSIS

  use Taranis::Config;

  my $obj = Taranis::Config->new( '/optional/path/to/alternative.xml' );

  $obj->getSetting( 'config setting' );

  $obj->saveSettings( %saveSettings );

  my $name = $config->publicationTemplateName(advisory => 'email');

  if($config->isEnabled('phishreferencemandatory')) { ...}

  if(my $c = $config->publishWebsite) ...

=head1 DESCRIPTION

This module is used for retrieving and editing settings stored in XML files. 
Mostly used for retrieving configuration settings from the main configuration file.

=head1 METHODS

=head2 new( '/optional/path/to/alternative.xml' )

Constructor of the C<Taranis::Config> module.
Takes a XML configuration file path as optional argument.
If the argument is undefined it will use the main configuration file specified in $mainconfig (normally
taranis.conf.xml).

    my $obj = Taranis::Config->new( '/opt/taranis/conf/taranis.conf.example.xml' );

OR

    my $obj = Taranis::Config->new();

Returns a blessed ARRAY containing the configuration.

=head2 getSetting( 'config setting' )

Method for retrieving one configuration setting. May be used as in OO context as well as direct use.
Takes one the configuration setting name as argument.

    my $config_setting = $cfg->getSetting( 'config setting' );

OR 

    my $config_setting = Taranis::Config->getSetting( 'config setting' );

Return the setting if present. If not it returns undef. 

=head2 saveSettings( %saveSettings )

Method for saving configuration settings back to file.

Takes a HASH with all the settings as argument.

    $obj->saveSettings( earthling => 'Arthur Dent', answer => 42, etc... );

Returns TRUE if saving of settings is ok. Returns FALSE if it fails, and will set C<< $obj->{errmsg} >> to the error generated by C<XML::Simple>. 

=head2 isEnabled($flag)

Returns '1' when the C<$flag> is 'on' (case-insensitive), otherwise '0'.

=head2 publishWebsite

Returns the configuration about the website connector plugin, when it
has been filled-in.  Otherwise, C<undef> is returned.  This method can
be used to detect whether website publication is enabled.

The returned HASH contains to entries:

=head1 DIAGNOSTICS

=over 4

=item implementation

Specifies the class which implements the coupling.  You may specify your
own implementation, which must extend L<Taranis::Website>.

=item configuration

Refers to an XML formatted file which contains the configuration for
the plugin.  The values are passed with instantion of the implementation.

=back

=cut

1;
