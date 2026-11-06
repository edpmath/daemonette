Name:           daemonette
# NOTE: This Version is only a fallback for manual local builds.
# CI (and any build driven by the packaging scripts) overrides it with the
# real version declared in meson.build — the single source of truth.
Version:        1.0.0
Release:        1%{?dist}
Summary:        Lightweight system tray process and service manager for developers
License:        MIT
URL:            https://github.com/edpmath/daemonette
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  vala
BuildRequires:  gcc
BuildRequires:  gtk3-devel
BuildRequires:  libayatana-appindicator-gtk3-devel
BuildRequires:  json-glib-devel
BuildRequires:  gee08-devel
BuildRequires:  desktop-file-utils
BuildRequires:  libappstream-glib

Requires:       gtk3
Requires:       libayatana-appindicator-gtk3
Requires:       json-glib
Requires:       libgee

%description
Daemonette is an ultra-lightweight desktop process manager for Linux,
designed for software developers and system administrators. It lives in
the system tray (AppIndicator) and provides instant access, status monitoring,
and control over local development servers, background watchers, and
microservices with near-zero memory footprint (~6 MB private RAM).

%prep
%autosetup

%build
%meson
%meson_build

%install
%meson_install

%check
%meson_test

%files
%license LICENSE
%doc README.md README.es.md
%{_bindir}/daemonette
%{_datadir}/applications/io.github.edpmath.Daemonette.desktop
%{_datadir}/metainfo/io.github.edpmath.Daemonette.metainfo.xml
%{_datadir}/icons/hicolor/*/apps/daemonette.png

%changelog
* Fri Nov 06 2026 Elias Peraza <edpmath@users.noreply.github.com> - 1.0.0-1
- Initial release
