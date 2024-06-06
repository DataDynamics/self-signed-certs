#!/usr/bin/env bash
#
# generates a wildcard (multi-domain) server certificate

set -e
# set -x

# certification domain
CA_DOMAIN=cm.pvc.datalake.net

# cert validity in days
DAYS=3690

# certificate name
NAME="star"

# domain
CN=*.pvc.datalake.net

# base directory
DIR="."

# ----

DNS=()
for _dns in $@
do
  if [ -z "$_dns" ]; then
    break
  fi
  DNS+=($_dns)
done

if [ ${#DNS[@]} -eq 0 ]; then
  # use default list
  DNS=("*.apps.pvc.datalake.net apps.pvc.datalake.net *.pvc.datalake.net" "pvc.datalake.net" "*.local" "localhost")
else 
  CN="${DNS[0]}"
  NAME=$(echo ${DNS[0]} | sed -e "s/^\*\./star./")
fi

count=${#DNS[@]}
index=0
ALTNAMES=""

while [ $index -lt $count ]; do
  ALTNAMES+="DNS.$((index+1)) = ${DNS[$index]}\n"
  index=$((index+1))
done

INI="$DIR/csr/$NAME.ini"

TYPE="root_ca"
FILES=()
if [ -f "$DIR/certs/intermediate.crt" ]; then
  FILES+=("$DIR/certs/$TYPE.crt")
  TYPE="intermediate"
fi

ROOT_PASS="$DIR/private/$TYPE.pass"
ROOT_KEY="$DIR/private/$TYPE.key"
ROOT_CRT="$DIR/certs/$TYPE.crt"

CRL="$DIR/crl/$TYPE.crl"
CRL_DATABASE="$DIR/crl/$TYPE.index.txt"
CRL_NUMBER="$DIR/crl/number"
CRL_DP="https://$CA_DOMAIN/$TYPE.crl"

TAR="$DIR/certs/$NAME.tgz"
ZIP="$DIR/certs/$NAME.zip"
KEY="$DIR/certs/$NAME.key"
CSR="$DIR/csr/$NAME.csr"
CRT="$DIR/certs/$NAME.crt"
PFX="$DIR/certs/$NAME.pfx"
PFX_PASS="$DIR/certs/$NAME.pfx.pass"
CRTKEY="$DIR/certs/$NAME.crt.key"

RANDFILE="$DIR/private/randfile"
SERIAL="$DIR/private/serial"

FILES+=($ROOT_CRT)
FILES+=($KEY)
FILES+=($CRT)
FILES+=($PFX)
FILES+=($PFX_PASS)
FILES+=($CRTKEY)

# ----

test -f "$KEY" && rm "$KEY" "$CSR" "$CRT" "$CRTKEY" "$PFX" "$PFX_PASS"

test ! -f $ROOT_CRT && ./root_ca.sh

# ----

(cat << EOS
[ ca ]
default_ca        = CA_default

[ CA_default ]
dir               = $DIR          
database          = $CRL_DATABASE
new_certs_dir     = $DIR/certs   
certificate       = $ROOT_CRT    
serial            = $SERIAL
rand_serial       = yes
private_key       = $ROOT_KEY
RANDFILE          = $RANDFILE
default_days      = $DAYS
default_crl_days  = 30 
default_md        = sha256
policy            = policy_any
email_in_dn       = no
name_opt          = ca_default
cert_opt          = ca_default
unique_subject    = no
copy_extensions   = copyall
crl_extensions    = crl_ext

[ policy_strict ]
countryName            = match
stateOrProvinceName    = match
organizationName       = match
organizationalUnitName = optional
commonName             = supplied
emailAddress           = optional

[ policy_any ]
countryName            = supplied
stateOrProvinceName    = optional
organizationName       = optional
organizationalUnitName = optional
commonName             = supplied
emailAddress           = optional

[ req ]
prompt              = no
default_bits        = 4096
default_days        = 375
default_md          = sha256
string_mask         = utf8only
distinguished_name  = req_distinguished_name
req_extensions      = v3_req

[ crl_ext ]
# Extension for CRLs (man x509v3_config).
authorityKeyIdentifier = keyid:always

[ req_distinguished_name ]
# Country Name (2 letter code)
C = KR
# State or Province Name
ST = Gyeonggi-do
# Locality Name
L = Yongin-si
# Organization Name
O = Data Dynamics
# Organizational Unit Name
#OU = Certification Unit
# Common Name
CN = $CN
# Email Address
emailAddress = info@$CN

[ v3_req ]
nsCertType = server
#nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = @alt_names
crlDistributionPoints = URI:$CRL_DP

[ alt_names ]
$(echo -e "$ALTNAMES")
#DNS.1 = *.aa.aa
#DNS.2 = aa.aa

EOS
) > $INI

# ----

#PASSWORD=$(openssl rand -base64 50 | tr -dc "[:print:]" | head -c 40)

PASSWORD="Dd98969321$9"

# ----

# generate key
openssl genrsa -out $KEY 4096

# create certificate signing request
echo "Creating CSR '$CSR'"
openssl req -new \
  -config $INI \
  -key $KEY -out $CSR

# sign certificate
echo "Signing certificate '$CRT' from '$CSR'"
openssl ca \
  -batch \
  -notext \
  -config "$INI" \
  -days $DAYS \
  -passin "file:$ROOT_PASS" \
  -in "$CSR" \
  -out "$CRT"

# chain crt with key (e.g. for HAProxy)
cat "$CRT" "$KEY" > "$CRTKEY"
echo "Chaining keys '$CRTKEY'"
cat $CRTKEY

# generate PKCS12
echo $PASSWORD > $PFX_PASS
echo "Generating PKCS12 '$PFX'"
openssl pkcs12 -export \
  -passout "file:$PFX_PASS" \
  -in "$CRT" -inkey "$KEY" \
  -certfile "$ROOT_CRT" \
  -out "$PFX"

# archive all
tar czf "$TAR" "${FILES[@]}"
zip -r "$ZIP" "${FILES[@]}"

# show certificate
echo "Showing certificate '$CRT'"
openssl x509 -text -noout -in "$CRT"
