#!/bin/sh
# check that the actual installer can work, ie. all required perl modules present.
# if not, complain and offer to help.

# note: this assumes that the current dir is the unpacked directory! (true in the .run environment)
if type perl >/dev/null 2>&1; then
		if perl -c ./install.pl 2>/dev/null; then
				exec ./install.pl "$@";
		fi
fi

cat >&2 <<EOF

Error: no Perl or Perl core modules installed!

NMIS (and this installer) require that Perl and the
core Perl modules are present on your system.

On CentOS/RedHat systems you need to install the packages
"perl-core" and "cpan" with:
sudo yum install perl-core cpan

on Debian/Ubuntu the package "perl" is required:
sudo apt-get install perl

Do you want the installer to install Perl for you?
EOF

# check for unattended -y mode
for i in "$@"; do
		if [ "$i" = "-y" ]; then
				UNATTENDED=1
				break;
		fi
done

# let's not even ask if -y mode is on
[ -n "$UNATTENDED" ] && DOIT=1 && EXTRA="-y" && DEBIAN_FRONTEND="noninteractive" && echo "Unattended Mode - default answer Y"
export DEBIAN_FRONTEND
# let's accept enter as yes
if [ -z "$UNATTENDED" ] && read -p "Enter y to continue, anything else to abort: "  X && [ -z "$X" -o "$X" = 'y' -o "$X" = 'Y' ]; then
		DOIT=1;
fi

if [ "$DOIT" = 1 ]; then
		if type yum >/dev/null 2>&1; then

				if type subscription-manager >/dev/null 2>&1 && egrep -q 'VERSION_ID="7' /etc/os-release 2>/dev/null; then
						echo "Enabling RHEL 7 Repositories"
						subscription-manager repos --enable rhel-7-server-optional-rpms \
																 --enable rhel-7-server-supplementary-rpms
				fi
				echo "Starting yum install"
				yum $EXTRA install perl-core

		elif type apt-get >/dev/null 2>&1; then
				echo "Starting apt-get install"
				apt-get $EXTRA install perl
		fi

		# time to try once more
		if type perl >/dev/null 2>&1; then
				if perl -c ./install.pl 2>/dev/null; then
						exec ./install.pl "$@";
				else
						echo "Perl is present, but lacking some of the required modules! " >&2
						perl -c ./install.pl
						exit 1
				fi
		fi
		exit 0
fi


echo "No Perl available, aborting installation." >&2
exit 1
