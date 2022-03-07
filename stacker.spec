Name: stacker
Version: 0.01
Release: 1%{?dist}
Summary: stacker is a tool for managing device-mapper stacks for testing
BuildArch: noarch

Group: System Environment/Base
License: GPL
Source0: stacker-%{version}.tar.bz2

Requires: bash device-mapper lvm2

%description
Stacker is a tool for creating and managing stacks of device-mapper devices for performance and comparitive testing purposes.
%prep
%setup -q

%build
make

%install
make ROOT=$RPM_BUILD_ROOT mandir=%{_mandir} install

%files
/usr/bin/stkr
%{_mandir}/man8/stkr.8.gz
%doc ChangeLog README COPYING

%changelog
* Tue Oct 12 2021 Bryn M. Reeves bmr@redhat.com = 0.01-1
- Initial spec file

