This directory contains gzipped diagnostic tarballs, named for build IDs known
to the Build Manager.

It's possible to deliver test-station specific tarballs by creating a
subdirectory here, named for the station ID, e.g. './73'. The system will look
there first for download requests from station 73.

There is also a ./fixtures directory which contains a tarball for each fixture
name referenced by the Station Mmanager, this is used by the Pionic controller
when it boots.

Note all downloadable tarball names  MUST end with '.tar.gz'.
