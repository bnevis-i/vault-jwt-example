#!/usr/bin/dumb-init /bin/sh

# Start the server (background)
docker-entrypoint.sh "$@" &

# Custom startup script

set -x

cd /vault/config
mkdir -p assets
cd assets

vault status
status=1

while [ $status -eq 1 ]; do
    vault status
    status=$?
    echo "Vault status, code = $status"
done

# set -e

if [ $status -eq 2 ]; then
    # Init if needed
    if [ ! -f vault-init.json ]; then
        echo "Initializing vault"
        vault operator init -key-shares=1 -key-threshold=1 -format=json > vault-init.json
    fi
    # Then unseal
    echo "Unsealing vault"
    vault operator unseal `jq -r '.unseal_keys_b64[0]' vault-init.json`

    export VAULT_TOKEN=`jq -r '.root_token' vault-init.json`
    echo "Vault root token: ${VAULT_TOKEN}"

    # Enabling audit will help us debug Vault calls
    vault audit enable file file_path=stdout

    # Enable KV secrets engine (version 1)
    vault secrets enable -version=1 -path=secrets kv

    # Enable username/password authentication
    vault auth enable userpass
    userpass_accessor=`vault auth list -format=json | jq -r '.["userpass/"].accessor'`

    # Create named key for JWT signing
    # (identity secrets engine is always enabled)
    vault write identity/oidc/key/edgex-identity algorithm=RS384 'allowed_client_ids=*'

    services="svc1 svc2 svc3"
    for service in ${services}; do
        cat | vault policy write ${service} - <<EOH
{
    "path": {
        "secret/edgex/${service}/*": {
            "capabilities": [ "create", "update", "delete", "list", "read" ]
        },
        "consul/creds/${service}": {
            "capabilities": [ "read" ]
        },
        "identity/oidc/token/${service}": {
            "capabilities": [ "read" ]
        },
        "identity/oidc/introspect": {
            "capabilities": [ "create", "update" ]
        }
    }
}
EOH
        entity_id=`vault write -format=json identity/entity name=${service} policies=${service} | jq -r '.data.id'`
        password=`openssl rand -base64 33`
        echo "${service}: ${password}"
        vault write auth/userpass/users/${service} password=${password}
        vault write identity/entity-alias name=${service} canonical_id=${entity_id} mount_accessor=${userpass_accessor}


        # https://brian-candler.medium.com/using-vault-as-an-openid-connect-identity-provider-ee0aaef2bba2
        jwt_template=$(cat | base64 -w 0 << EOF
{
    "name": {{identity.entity.name}}
}
EOF
)
        vault write identity/oidc/role/${service} name=${service} key=edgex-identity client_id=urn:openziti ttl=24h template="${jwt_template}"
        user_token=`vault login -format=json -method=userpass -path=userpass username=${service} password=${password} | jq -r '.auth.client_token'`
        echo "${user_token}" > ${service}_vault_token.txt
        VAULT_TOKEN=${user_token} vault read -format=json identity/oidc/token/${service} | jq -r '.data.token' > ${service}_jwt.txt
        echo `cut -d. -f2 ${service}_jwt.txt`== | tr '[-_]' '[+/]' | base64 -d | jq > ${service}.claims.txt
        cat ${service}.claims.txt
    done

    echo ""
    echo "Check /vault/config/assets for interesting stuff"

fi

echo "OIDC well-known configuration: "
curl -s -k "${VAULT_ADDR}/v1/identity/oidc/.well-known/openid-configuration" | jq

echo "OIDC JWKS: "
curl -s -k "${VAULT_ADDR}/v1/identity/oidc/.well-known/keys" | jq


# Block on vault
wait