Name:           millennium-helpers-bin
Version: 2.7.0
Release: 1%{?dist}
Summary:        Millennium helpers (prebuilt release assets)
License:        MIT
URL:            https://github.com/bolens/millenium-helpers
%global source_sha256 96baa9285be191a136aab460ba4e75edc426842333b7df8f719c8de724730ca1
Source0:        https://github.com/bolens/millenium-helpers/releases/download/v%{version}/millennium-helpers-v%{version}-linux-amd64.tar.gz
# Source0 sha256: %{source_sha256}

Requires:       bash, curl, unzip, python3
Provides:       millennium-helpers = %{version}-%{release}
Conflicts:      millennium-helpers, millennium-helpers-git
BuildArch:      noarch

%description
Scripts/MCP from the published Linux release tarball. Installs bin/millennium
when the Go dispatcher is embedded in the asset.

%prep
%setup -c -n millennium-helpers-%{version}

%build
# Prebuilt release payload — nothing to compile.

%install
install -d %{buildroot}%{_bindir} \
  %{buildroot}%{_libdir}/millennium-helpers \
  %{buildroot}%{_datadir}/bash-completion/completions \
  %{buildroot}%{_datadir}/zsh/site-functions \
  %{buildroot}%{_datadir}/fish/vendor_completions.d \
  %{buildroot}%{_datadir}/nushell/completions \
  %{buildroot}%{_mandir}/man1 \
  %{buildroot}%{_licensedir}/%{name}

if [ ! -x bin/millennium ]; then
  echo "error: release tree missing bin/millennium (Go dispatcher required)" >&2
  exit 1
fi
# Long-name PATH entries are argv0 twins of the Go dispatcher.
for twin in millennium millennium-mcp millennium-repair millennium-upgrade \
  millennium-schedule millennium-purge millennium-diag millennium-theme
do
  install -m755 bin/millennium %{buildroot}%{_bindir}/$twin
done
install -m644 VERSION %{buildroot}%{_libdir}/millennium-helpers/VERSION
install -m644 completions/bash/millennium-helpers %{buildroot}%{_datadir}/bash-completion/completions/millennium-helpers
for s in millennium millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp; do
  ln -sf millennium-helpers %{buildroot}%{_datadir}/bash-completion/completions/$s
done
install -m644 completions/zsh/_millennium-helpers %{buildroot}%{_datadir}/zsh/site-functions/_millennium-helpers
for s in millennium millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp; do
  ln -sf _millennium-helpers %{buildroot}%{_datadir}/zsh/site-functions/_$s
done
install -m644 completions/fish/*.fish %{buildroot}%{_datadir}/fish/vendor_completions.d/
install -m644 completions/nushell/millennium-helpers.nu %{buildroot}%{_datadir}/nushell/completions/
install -m644 man/*.1 %{buildroot}%{_mandir}/man1/
install -m644 LICENSE %{buildroot}%{_licensedir}/%{name}/LICENSE

%files
%license LICENSE
%{_bindir}/millennium*
%{_libdir}/millennium-helpers/
%{_datadir}/bash-completion/completions/millennium*
%{_datadir}/zsh/site-functions/_millennium*
%{_datadir}/fish/vendor_completions.d/millennium*
%{_datadir}/nushell/completions/millennium-helpers.nu
%{_mandir}/man1/millennium*.1*

%changelog
* Tue Jul 14 2026 bolens <https://github.com/bolens> - 2.6.2-1
- Binary/asset package from Linux release tarball
