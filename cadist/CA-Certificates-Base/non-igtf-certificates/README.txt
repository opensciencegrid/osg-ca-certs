This svn directory (cadist/trunk/CA-Certificates-Base/non-igtf-certificates)
contains the files from CAs not accredited by the IGTF that are included
in the OSG CA distribution.

Whenever a new CA is added to the OSG distribution the appropriate
files are to be added in this repository as described below.

Files are named following the IGTF naming convention which has a
unique alias for each CA as <alias>.<ext> where
  <alias> is the unique name for each CA
  <ext> is the extension name, which are
      pem = PEM format X.509 certificate of the CA
      info = name=value pairs of metadata for the CA
      crl_url = the URL for downloading the current CRL for the CA
      signing_policy = Globus signing policy file
      namespaces = file generated by IGTF from the signing_policy file
      install = a file that installs the CA files to the distribution location


For each CA the new hash value and the old hash value are computed
using openssl V1.x as

NEWHASH = openssl x509 -in <alias>.pem -noout -subject_hash
OLDHASH = openssl x509 -in <alias>.pem -noout -subject_hash_old

The <alias>.install file is executed as
./<alias>.install <dir> <version>  [old]
where <dir> is the distribution directory and, if the 3rd argument [old]
is not given, it installs the new format as:

  foreach <ext> not like install
    cp <alias>.<ext> <dir>

  foreach <ext> not like install, pem
    ln -s <dir>/<alias.<ext> OLDHASH.<ext>
    ln -s <dir>/<alias.<ext> NEWHASH.<ext>

  ln -s <dir>/<alias>.pem OLDHASH.0
  ln -s <dir>/<alias>.pem NEWHASH.0


The <alias>.info consists of lines of name = value parameter pairs 
and # is used as a comment delimiter.  You can look at examples in 
the IGTF distribution. At minimum there should be values for parameters
alias, crl_url, status, url.

Note that <alias>.info should NOT include version as this will be
added automatically.

And if the 3rd argument, old (or any value), is given then the CA files
are installed with their old hash value names and no symlinks.
 

*******************
Created 27 April 2010 by D. Olson
Updated 28 Sept 2010 by D. Olson - option to install old layout also

