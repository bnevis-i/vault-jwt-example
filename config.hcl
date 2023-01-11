listener "tcp" { 
    address = "edgex-vault:8200" 
    tls_disable = "1" 
    cluster_address = "edgex-vault:8201" 
} 

backend "file" {
    path = "/vault/file"
} 

default_lease_ttl = "168h" 
max_lease_ttl = "720h"
