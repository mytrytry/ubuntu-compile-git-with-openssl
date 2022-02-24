#!/usr/bin/env bash
set -e

# Gather command line options
for i in "$@"; do 
  case $i in 
    -skiptests|--skip-tests) # Skip tests portion of the build
    SKIPTESTS=YES
    shift
    ;;
    -d=*|--build-dir=*) # Specify the directory to use for the build
    BUILDDIR="${i#*=}"
    shift
    ;;
    -skipinstall|--skip-install) # Skip dpkg install
    SKIPINSTALL=YES
    ;;
    *)
    #TODO Maybe define a help section?
    ;;
  esac
done

# Use the specified build directory, or create a unique temporary directory
BUILDDIR=${BUILDDIR:-$(mktemp -d)}
echo "BUILD DIRECTORY USED: ${BUILDDIR}" 
mkdir -p "${BUILDDIR}"
cd "${BUILDDIR}"

# Download the source tarball from GitHub
apt update
apt install curl -y

# get latest version

command -v gojq || go get github.com/itchyny/gojq/cmd/gojq
git_tag=$(curl -Ssf https://api.github.com/repos/git/git/tags | gojq '.[0].name' | tr -d '"')

git_tarball_url="https://github.com/git/git/archive/refs/tags/${git_tag}.tar.gz"
echo "DOWNLOADING FROM: ${git_tarball_url}"

curl -LZ --retry 5 "${git_tarball_url}" --output "git-source.tar.gz"
tar -xf "git-source.tar.gz" --strip 1

# Source dependencies
# Don't use gnutls, this is the problem package.
apt remove --purge libcurl4-gnutls-dev -y || true
# Using apt-get for these commands, they're not supported with the apt alias on 14.04 (but they may be on later systems)

#sudo apt-get autoremove -y
#sudo apt-get autoclean

# Meta-things for building on the end-user's machine
apt install build-essential autoconf dh-autoreconf -y
# Things for the git itself
apt install libcurl4-openssl-dev tcl-dev gettext asciidoc -y
apt install libexpat1-dev libz-dev -y

apt install libsecret-1-dev -y

# Build it!
make configure
# --prefix=/usr
#    Set the prefix based on this decision tree: https://i.stack.imgur.com/BlpRb.png
#    Not OS related, is software, not from package manager, has dependencies, and built from source => /usr
# --with-openssl
#    Running ripgrep on configure shows that --with-openssl is set by default. Since this could change in the
#    future we do it explicitly
./configure --prefix=/usr --with-openssl

# set gitexecdir to the same as [ubuntu](https://packages.ubuntu.com/groovy/amd64/git/filelist) and archlinux
_make_paths=(
  prefix='/usr'
  gitexecdir='/usr/lib/git-core'
  perllibdir="$(/usr/bin/perl -MConfig -wle 'print $Config{installvendorlib}')"
)

_make_options=(
  INSTALL_SYMLINKS=1
  MAN_BOLD_LITERAL=1
  NO_PERL_CPAN_FALLBACKS=1
  USE_LIBPCRE2=1
)

make "${_make_paths[@]}" "${_make_options[@]}" -j$(($(nproc)+2)) all man

# ref https://github.com/archlinux/svntogit-packages/blob/4864e39da0bc99e373f3cb728272a93d66b58cd6/trunk/PKGBUILD#L63
# As stated by the Debian team: [libgnome-keyring0 is deprecated](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=892359) in favor of libsecret[https://wiki.gnome.org/Projects/Libsecret]
# Deprecate libgnome-keyring. Use libsecret instead https://gitlab.gnome.org/GNOME/libgnome-keyring/commit/6a5adea4aec93
make -C contrib/credential/libsecret

if [[ "${SKIPTESTS}" != "YES" ]]; then
  make test
fi

# Install
if [[ "${SKIPINSTALL}" != "YES" ]]; then
  # If you have an apt managed version of git, remove it
  if apt remove --purge git -y; then
    echo "old git purged"
    #sudo apt-get autoremove -y
    #sudo apt-get autoclean
  fi
  # Install the version we just built
  make "${_make_paths[@]}" "${_make_options[@]}" install install-man #install-doc install-html install-info

  # libsecret credentials helper
  install -m 0755 contrib/credential/libsecret/git-credential-libsecret \
    /usr/lib/git-core/git-credential-libsecret

  echo "Make sure to refresh your shell!"
  bash -c 'echo "$(which git) ($(git --version))"'
fi
