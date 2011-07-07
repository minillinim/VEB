#!/usr/bin/perl
###############################################################################
#
#     buildKVMmachine.pl
#    
#    Main wrapper for building vms from config system
#    
#    RELIES ON ENVIRONMENT VARIABLE $VEB_ROOT
#    (should be set to the folder above the one where this file resides)
#
#    Copyright (C) 2011 Michael Imelfort
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

#pragmas
use strict;
use warnings;

#core Perl modules
use Getopt::Long;

#CPAN modules
use Data::Dumper;

#locally-written modules

BEGIN {
    select(STDERR);
    $| = 1;
    select(STDOUT);
    $| = 1;
}

# get input params and print copyright
printAtStart();
my $options = checkParams();

######################################################################
# 
# This script has two main phases; 
# 
# 1. Build a shell script which can be used to build a VM using ubuntu-vm-builder
# 2. Output or execute this script
# 
######################################################################

# Globals:
# Get the VEB root
my $global_veb_root = `echo \$VEB_ROOT`;
chomp $global_veb_root;

# load the conf file. Should be in the root dir and called veb.conf 
# this will populate these global variables
my $global_image_dest = "/dev/null/";
my $global_image_xml_dest = "/dev/null/";
my %global_active_hardware = ();
loadVebConf();

# make a random name so that we can store files somewhere temporarily
my $global_random_name = "veb_".getTimestamp();

#
# machine defaults
#
my $global_root_username = "bioadmin";
if(exists $options->{'user'}) { $global_root_username = $options->{'user'}; }
my $global_root_password = "password";
if(exists $options->{'pass'}) { $global_root_password = $options->{'pass'}; }
my $global_hostname = "ubuntu_".$options->{'cpus'}."_".$options->{'mem'}."_".$options->{'ip'};
if(exists $options->{'hostname'}) { $global_hostname = $options->{'hostname'}; }

#
# Load machine specs from file (if possible)
# 
my %global_machine = ();
loadMachineConfig($options->{'config'});

#
# virtual packages make vm-builder crash...
#
my %global_virtual_defaults = ();
my %global_apps_blacklist = ();
loadVirtualDefaults($options->{'config'});

#
# START vm-builder script
#
my $global_vm_script = "#!/bin/bash";
$global_vm_script .= "\nVEB_ROOT_USER=\"$global_root_username\"";

# 
# ADD FIRST BOOT SCRIPT
# 
addFirstBootScripts();

# 
# ADD FIRST LOGIN SCRIPT
# 
addFirstLoginScripts();

# 
# VMBUILDER START
# 
$global_vm_script .= "\nvmbuilder kvm ubuntu -v \\";
$global_vm_script .= "\n--libvirt=qemu:///system \\";
$global_vm_script .= "\n--destdir  $global_image_dest/$global_hostname \\";
$global_vm_script .= "\n--mirror ".$global_machine{'mirror'}." \\";
$global_vm_script .= "\n--arch ".$global_machine{'arch'}." \\";
$global_vm_script .= "\n--suite ".$global_machine{'suite'}." \\";
$global_vm_script .= "\n--bridge ".$global_machine{'bridge'}." \\";
$global_vm_script .= "\n--user \$VEB_ROOT_USER \\";
$global_vm_script .= "\n--pass $global_root_password \\";
$global_vm_script .= "\n--hostname $global_hostname \\";
$global_vm_script .= "\n--firstboot \$(pwd)/firstboot \\";

# add the number of cores and memory
$global_vm_script .= "\n--mem ".$options->{'mem'}." \\";
$global_vm_script .= "\n--cpus ".$options->{'cpus'}." \\";

#
# Fix network stuff
#
$global_vm_script .= "\n--ip ".$options->{'ip'}." \\";
my @ip_parts = split /\./, $options->{'ip'};
my $ip_front = $ip_parts[0].".".$ip_parts[1].".".$ip_parts[2].".";

$global_vm_script .= "\n--mac ";
if(exists $options->{'mac'}) { $global_vm_script .= $options->{'mac'}." \\"; } else { $global_vm_script .= makeRandom_KVM_Mac() . " \\"; }
$global_vm_script .= "\n--mask ";
if(exists $options->{'mask'}) { $global_vm_script .= $options->{'mask'}." \\"; } else { $global_vm_script .= "255.255.255.0 \\"; }
$global_vm_script .= "\n--net ";
if(exists $options->{'net'}) { $global_vm_script .= $options->{'net'}." \\"; } else {  $global_vm_script .= $ip_front."0 \\" ;}
$global_vm_script .= "\n--bcast ";
if(exists $options->{'bcast'}) { $global_vm_script .= $options->{'bcast'}." \\"; } else {  $global_vm_script .= $ip_front."255 \\" ;}
$global_vm_script .= "\n--gw ";
if(exists $options->{'gw'}) { $global_vm_script .= $options->{'gw'}." \\"; } else {  $global_vm_script .= $ip_front."1 \\" ;}
$global_vm_script .= "\n--dns ";
if(exists $options->{'dns'}) { $global_vm_script .= $options->{'dns'}." \\"; } else {  $global_vm_script .= "130.102.2.15 \\" ;}

# 
# ADD APPS
# 
$global_vm_script .= "\n".addApps();
$global_vm_script .= "-o\n\n\n";


# 
# EXECUTE OR PRINT
# 
if(exists $options->{'no_action'})
{
    print $global_vm_script;
}
else
{
    # make a temp dir
    my $this_dir = `pwd`;
    mkdir "/tmp/$global_random_name/";
    chdir "/tmp/$global_random_name/";
    
    # write the script to file
    open my $shfh, ">", "/tmp/$global_random_name/$global_random_name.sh" or die $!;
    print $shfh $global_vm_script;
    close $shfh;
    
    # run the script
    `sh $global_random_name.sh`;
    
    # clean up
    chdir $this_dir;
    `rm -rf /tmp/$global_random_name`;
}

######################################################################
# CUSTOM SUBS
######################################################################
sub loadVebConf {
    #-----
    # Load global config options
    #
    open my $vcfh, "<", $global_veb_root."/veb.conf" or die $!;
    while(<$vcfh>)
    {
        next if $_ =~ /^#/;
        next if $_ =~ /^$/;
        chomp $_;
        my @fields = split / /, $_;
        if($fields[0] eq "workhorse")
        {
            $global_active_hardware{$fields[1]} = 1;
        }
        elsif($fields[0] eq "image_store")
        {
            $global_image_dest = $fields[1];
        }
        elsif($fields[0] eq "image_XML_store")
        {
            $global_image_xml_dest = $fields[1];
        }
        else
        {
            die("**Error -- Unknown line: $_ in veb.conf\n");
        }
    }
    close $vcfh;
}

sub makeRandom_KVM_Mac {
    #-----
    # return a KVM compatible MAC address
    # see https://help.ubuntu.com/community/KVM/Networking for MACADDR comment .
    #
    my $tmp_mac = "52:54:".`dd if=/dev/urandom count=1 2>/dev/null | md5sum | sed -e 's/^\\(..\\)\\(..\\)\\(..\\)\\(..\\).*/\\1:\\2:\\3:\\4/'`;
    chomp $tmp_mac;
    return $tmp_mac;
}

sub getTimestamp {
    #-----
    # Used to make a random name for tmp storage
    #
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    return $mday.$mon.$year."_".$hour.$min.$sec;
}

sub loadVirtualDefaults {
    #-----
    # Some apps cause problems with vm builder because they are virtual
    # others because the automaitc script includes conflicts
    # this function reads in defaults for virts and blacklisted 
    # apps. All done by hand!
    # 
    my ($machine_name) = @_;
    my $def_path = "$global_veb_root/machines/$machine_name/virtual_defaults.dat";
    print "Loading defaults for virtual packages from: $def_path\n";
    open my $vfh, "<", $def_path or die $!;
    while(<$vfh>)
    {
        next if($_ =~ /^#/);
        next if($_ =~ /^ /);
        next if($_ =~ /^$/);
        chomp $_;
        my @fields = split /:/, $_;
        $global_virtual_defaults{$fields[0]} = $fields[1];
    }
    close $vfh;
        
    my $black_path = "$global_veb_root/machines/$machine_name/package_blacklist.dat";
    print "Loading package blacklist from: $black_path \n";
    open my $vbfh, "<", $black_path or die $!;
    while(<$vbfh>)
    {
        next if($_ =~ /^#/);
        next if($_ =~ /^ /);
        next if($_ =~ /^$/);
        chomp $_;
        $global_apps_blacklist{$_} = 1;
    }
    close $vbfh;
}    

sub loadMachineConfig {
    #-----
    # Load information about this machine from the db
    #
    my ($machine_name) = @_;
    my %allowable_fields = ( 'apps' => 1, 
                             'part' => 1, 
                             'firstboot' => 1, 
                             'firstlogin' => 1,
                             'mirror' => 1,
                             'arch' => 1,
                             'suite' => 1,
                             'bridge' => 1,f
                             );
    
    my $machine_path .= "$global_veb_root/machines/$machine_name/machine.mvb";
    
    open my $mfh, "<", $machine_path or die "ERROR: cannot find machine: \"$machine_name\" at: \"$machine_path\"\n";
    while(<$mfh>)
    {
        next if($_ =~ /^#/);
        next if($_ =~ /^ /);
        next if($_ =~ /^$/);
        chomp $_;
        my @fields = split /\?/, $_;
        if(exists $allowable_fields{$fields[0]})
        {
            if(exists $fields[1])
            {
                # could possibly do a little more checking here...
                $global_machine{$fields[0]} = $fields[1];
            }
        }
        else
        {
            die "ERROR: Unknown text \"".$fields[0]."\" in file: \"$machine_path\"\n";
        }
    }
    close $mfh;
}

sub addFirstBootScripts
{
    #-----
    # Build the first boot script, take this from the apps paths
    #

    $global_vm_script .= "\ncat > firstboot <<EOF";
    $global_vm_script .= "\n#!/bin/sh";
    $global_vm_script .= "\nsleep 3\n";      # wait for the network to come up!
    my @apps = split /,/, $global_machine{'apps'};
    my $all_apps = "";
    my $first = 1;
    foreach my $app (@apps)
    {
        my $apps_path .= "$global_veb_root/apps/$app/$app".".fbs";
        open my $afh, "<", $apps_path or die "ERROR: cannot find app script conf: \"$app\" at: \"$apps_path\"\n";
        while(<$afh>)
        {
            $global_vm_script .= $_;
        }
        close $afh;
    }
    
    $global_vm_script .= "\nEOF";
}

sub addFirstLoginScripts
{
    #-----
    # Build the first login script, take this from the apps paths
    #
}

sub addApps {
    #-----
    # add applications to the server
    #
    my @apps = split /,/, $global_machine{'apps'};
    my $all_apps = "";
    my $first = 1;
    foreach my $app (@apps)
    {
        my $apps_path .= "$global_veb_root/apps/$app/$app".".avb";
        open my $afh, "<", $apps_path or die "ERROR: cannot find app conf: \"$app\" at: \"$apps_path\"\n";
        while(<$afh>)
        {
            next if($_ =~ /^#/);
            next if($_ =~ /^ /);
            next if($_ =~ /^$/);
            chomp $_;
            if($first != 1)
            {
                $all_apps .= ",";
            }
            $all_apps .= $_;
            $first = 0;
        }
        close $afh;
    }
    my @individ_apps = split /\n/, `addpkgs.sh -p $all_apps`;
    my $ret_apps = "";
    foreach my $app (@individ_apps)
    {
        next if(exists $global_apps_blacklist{$app} );
        if(exists $global_virtual_defaults{$app})
        {
            $ret_apps .= "--addpkg  ".$global_virtual_defaults{$app}." \\\n";
        }
        else
        {
            $ret_apps .= "--addpkg  ".$app." \\\n";
        }
    }
    return $ret_apps;
}

######################################################################
# TEMPLATE SUBS
######################################################################
sub checkParams {
    my @standard_options = ( "help|h+", "cpus:i", "mem:i", "config|c:s", "name|n:s", "no_action+", "hostname|h:s","user|u:s","pass|p:s","ip:s","mac:s","mask:s","net:s","bcast:s","gw:s","dns:s" );
    my %options;

    # Add any other command line options, and the code to handle them
    # 
    GetOptions( \%options, @standard_options );

    # if no arguments supplied print the usage and exit
    #
    exec("pod2usage $0") if (0 == (keys (%options) ));

    # If the -help option is set, print the usage and exit
    #
    exec("pod2usage $0") if $options{'help'};

    if(!exists $options{'config'} ) { print "**ERROR: You need to supply a machine config file\n"; exec("pod2usage $0"); }
    if(!exists $options{'name'} ) { print "**ERROR: You need to supply a machine image name\n"; exec("pod2usage $0"); }
    if(!exists $options{'cpus'} ) { print "**ERROR: You need to supply the number of cores\n"; exec("pod2usage $0"); }
    if(!exists $options{'mem'} ) { print "**ERROR: You need to supply the memory size\n"; exec("pod2usage $0"); }
    if(!exists $options{'ip'} ) { print "**ERROR: You need to supply the IP address of the machine\n"; exec("pod2usage $0"); }
    
    if($options{'cpus'} > 16) { print "**ERROR: Max cpus is 16\n"; exec("pod2usage $0"); }
    if($options{'mem'} > 254) { print "**ERROR: Memory size must be less than 255\n"; exec("pod2usage $0"); }
    
    $options{'mem'} = $options{'mem'} * 1024;
    
    return \%options;
}

sub printAtStart {
print<<"EOF";
---------------------------------------------------------------- 
 $0
 Copyright (C) 2011 Michael Imelfort
    
 This program comes with ABSOLUTELY NO WARRANTY;
 This is free software, and you are welcome to redistribute it
 under certain conditions: See the source for more details.
---------------------------------------------------------------- 
EOF
}

__DATA__

=head1 NAME

     buildKVMmachine.pl

=head1 COPYRIGHT

   copyright (C) 2011 Michael Imelfort

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 DESCRIPTION

   This script wraps a number of different scripts in the veb/src folder 
   and builds the actual vm.

=head1 SYNOPSIS

     buildKVMmachine.pl -name|n machine_name -config|c config_file -ip ADDR <options>

    # Build environment specific parameters
      -config -c config_file    Name of a machine config file (.mvb) which should be located in the db directory
      -name -n machine_name     Name of the final image
    
    # MACHINE specific parameters
      -cpus  CORES              Number of cores to give this image
      -mem   GB                 Memory in GB
      [hostname -h]             (optional) Hostname for the machine [default: ubuntu_CPUS_MEM_IP]
      [user -u]                 (optional) Root user account        [default: bioadmin]
      [pass -p]                 (optional) Password for root user   [default: password]
      
    # NETWORK specific parameters
        These are fed directly into python-vm-builder. See that manual for formats and restrictions!
      ip ADDR                   IP address in dotted form
      [mac]                     (optional) MAC address of the machine [default: randomly generated]
      [mask]                    (optional) IP mask in dotted form [default: 255.255.255.0]
      [net]                     (optional) IP net address in dotted form [default XX.XX.XX.0 where "XX"s are from IP addr]
      [bcast]                   (optional) IP broadcast in dotted form [default XX.XX.XX.255 where "XX"s are from IP addr]
      [gw]                      (optional) Gateway (router) address in dotted form [default XX.XX.XX.1 where "XX"s are from IP addr]
      [dns]                     (optional) DNS address in dotted form [default: 130.102.2.15 UQ addr]
    
    # MISC
      [-no_action]              Output the created shell script to stdout, do nothing "REAL"
      [-help -h]                Displays basic usage information
=cut
