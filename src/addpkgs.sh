#!/bin/bash
###############################################################################
#
#    addpkgs.sh
#    
#    Get all the deps for a list of packages and format strings for inclusion in 
#    a vmbuilder script
#    
#    Depends on apt-rdepends / ubuntu environment and basic shell stuff
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

# get opts
usage="Usage: $0 -p package1[,package2,...] [-h]"
no_opts=1
while getopts "p:h" o; do
    case "$o" in
        p)  packages="$OPTARG"; no_opts=0;;
        h)  echo $usage; exit 1;;
    esac
done
if [ "$no_opts" -eq "1" ]
then
    echo $usage; exit 1
fi

fixed_packages=`echo $packages | sed -e "s/,/ /g"`
cmd="apt-rdepends $fixed_packages 2> /dev/null | sed -e \"s/[ ]*PreDepends:[ ]*//\" -e \"s/[ ]*Depends:[ ]*//\" -e \"s/ (.*)//\" | sort | uniq | grep -ve \"^\$\""
eval $cmd
