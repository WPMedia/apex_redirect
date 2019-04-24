# APEX_REDIRECT

## Description

In DNS an "Apex" record is the placeholder at the top of a DNS zone (e.g. google.com). Unfortunatly for historical reasons the Apex entry can ONLY be a A, NS or SOA record and the exclusion of a CNAME causes difficulties with using a dynamic load balancer such as AWS ELB due to the fact they change the underlying IP address of the service on a regular basis.

## Challenge

Redirecting HTTP from domain.com to www.domain.com is trivial and can be accomplished with a one-line redirect in most web servers (such as nginx). Redirecting HTTPS (TLS) is far more difficult since you need a valid and trusted certificate in order to provide the 302 redirect message to the caller.

LetsEncrypt makes this easy and without cost, but dealing with the ACME protocol for proving ownership has its issues. The ACME protocol HTTP-01 allows a simple challenge/response provided over HTTP and for a single Apex server this is still easily accomplished given the command-line tool "certbot" knows hows to edit Nginx / Apache configs to accomplish both the challenge and installing the certificates.

### Multi-Server ACME HTTP-01 challenge

Given the goal is to create certificates "on-the-fly" when a request arrives at our Apex server this becomes slightly more complicated. When "CertBot" is initiated on one of the servers, the ACME servers will expect any server listed in the domain DNS to be able to reply to the challenge. CertBot's own documentation discusses this in depth and suggests using DNS-01 to handle the challenge but this would mean giving the Apex server credentials to be able to alter DNS and for many reasons that violates the design goal here.


By using a bit of LUA code within the NginX/OpenResty server we can create a way to distribute the challenge/response amongst the serverpool. In acme-http.conf there is a location statement which is used to "set" the challenge/response. It relies on a function is_my_peer which can be found within the file to validate the caller and it will only allow servers represented by the DNS A record we are managing to set a value in the acme_tokens K/V store

The entry has a TTL of 600 seconds (ten minutes) eliminating the need for any type of clean-up maintenance. Internally the token is stored as domain:token preventing any type of collision (while unlikely, easy to code for)

```
    location ~ ^/.well-known/acme-challenge/(.+)/(.+) {
        set $acme_token $host:$1;
        set $acme_reply $2;

        access_by_lua_block {
            ngx.exit(is_my_peer(ngx.var.host, ngx.var.remote_addr))
        }

        content_by_lua_block {
            local acme_tokens = ngx.shared.acme_tokens
            local status, error = acme_tokens:set(ngx.var.acme_token, ngx.var.acme_reply, 600)
            if status then
                ngx.status=200
                ngx.exit(ngx.OK)
            else
                ngx.status=404
                ngx.say(error)
                ngx.exit(ngx.OK)
            end
        }
    }
```

The "getter" method shown below allows retrieval of the challenge by any caller, returning a 404 if the token is not found in the table

```
    location ~ ^/.well-known/acme-challenge/([^/]+)$ {
        set $acme_token $host:$1;

        content_by_lua_block {
            local acme_tokens = ngx.shared.acme_tokens
            local reply = acme_tokens:get(ngx.var.acme_token)
            if (reply == nil or reply == '') then
                ngx.status=404
                ngx.exit(ngx.OK)
            else
                ngx.status=200
                ngx.say(reply)
                ngx.exit(ngx.OK)
            end
        }
    }
```

### Certificate Distribution and LetsEncrypt Servers

While it is possible for two independent servers to request a certificate for the same "Common Name" but ACME servers have rate limits which could easily be exceeded. During development I forgot to use the --test-server flag and learned first hand about the 1 WEEK lockout for violating the rate limiters.

So the next challenge is to distribute the Cert/Key to the other servers handling the target Apex domain. Since we already have a method to identify "peers" security concers are already addressed. Creating a route that allow "storing" and "retrieval" of PEM certficates was the next step in the process. This route allows both a POST operation to store the PEM material, along with a GET to fetch the data from the lua shared table named "acme_certs". Unlike the table for tokens, this table is allocated at 10mb of memory and does not have a TTL defined

```
    location ~ ^/.well-known/acme-(cert|chain|fullchain|privkey|certbot)$ {
        set $acme_domain $host;
        set $acme_type $1;

        access_by_lua_block {
            ngx.exit(is_my_peer(ngx.var.acme_domain, ngx.var.remote_addr))
        }

        content_by_lua_block {
            local acme_certs = ngx.shared.acme_certs

            -- If method is POST, then read the body with a Continue
            --
            if (ngx.var.request_method == "POST") then
                ngx.req.read_body()
                data = ngx.req.get_body_data()
                acme_certs:set(ngx.var.acme_domain .. ":" .. ngx.var.acme_type, data)
                ngx.status=200
                ngx.exit(ngx.status)

            -- Otherwise we are handling a GET
            --
            else
                cert = acme_certs:get(ngx.var.acme_domain .. ":" .. ngx.var.acme_type)
                if cert == nil then
                    ngx.status=404
                    ngx.exit(ngx.status)
                else
                    ngx.status=200
                    ngx.say(cert)
                    ngx.exit(ngx.status)
                end
            end
        }
    }
```

Not only does this make store/retieval of certificates a simple operation, LUA also support altering certificates on-the-fly so in the SSL server configuration the following exists. This method is invokes AFTER the SNI is transmitted from client to server so fetching the fullchain and privkey from the acme_certs shared memory is performed. Unless both Cert/Key are availible the function returns causing a fall-through to the static cert in the container (CN=localhost) but it causes a log entry to be written allowing supervisor to create a certficate

```
    ssl_certificate_by_lua_block {
        local ssl = require "ngx.ssl"

        -- Fetch cert from shared mem
        --
        local acme_certs = ngx.shared.acme_certs
        local fullchain = acme_certs:get(ssl.server_name() .. ":fullchain")
        local privkey = acme_certs:get(ssl.server_name() .. ":privkey")

        if (fullchain == nil or privkey == nil) then
            return
        end

        -- convert pem keys to der
        --
        local der_cert_chain, err = ssl.cert_pem_to_der(fullchain)
        if not der_cert_chain then
            ngx.log(ngx.ERR, "failed to convert certificate chain ", "from PEM to DER: ", err)
            return ngx.exit(ngx.ERROR)
        end

        local der_pkey, err = ssl.priv_key_pem_to_der(privkey)
        if not der_pkey then
            ngx.log(ngx.ERR, "failed to convert private key ", "from PEM to DER: ", err)
            return ngx.exit(ngx.ERROR)
        end

        -- Put keys in place
        --
        local ok, err = ssl.set_der_cert(der_cert_chain)
        if not ok then
            ngx.log(ngx.ERR, "failed to set DER cert: ", err)
            return ngx.exit(ngx.ERROR)
        end

        local ok, err = ssl.set_der_priv_key(der_pkey)
        if not ok then
            ngx.log(ngx.ERR, "failed to set DER private key: ", err)
            return ngx.exit(ngx.ERROR)
        end
    }
```

## Managing the Creation and Distribution of Certificates

This project is designed to run in a docker container and makes use of SupervisorD to launch the necessary processes. Besides launching OpenResty (Nginx) there is a Bash script "manage_certs" which runs and periodically looks for domains requiring certificates, along with handling the distibution to neighbors.

Lastly, rather than handle certificate creating/retrieval as an "exception" on the first request for a new domain, there are two methods in use to determine the starting list.

- an Environment Variable "SEED_DOMAIN" is used to determine a list of IP addresses which are potential peers of the service. Any server distributing certificates/tokens to an Apex server is added to the seed list.

- During the periodic processing the "seed" hosts are queried for a list of domains which they have certificates for. The queried server looks at each certificate/domain in it's possession and using the same "is_my_peer" method decides if the domain is included in the return list.

- Before evaluating "potential targets" for a certificate, the manager attempts to "fetch" certificates for each domain discovered through the "/.well-known/acme-domains" route. For each domain, the DNS records are fetched (further expanding the seed pool) and valid certificates are fetched through this process.

A note about the above process, there is a "PEM" entry called acme-certbot which is used (and fetched) to provide a Mutex to limit the likelyhood that two Apex servers will attempt to create certificates. This is not atomic, it is simply to "reduce" the likelyhood.

If after all of above a certificate is still required then the manager initiates the process through certbot to create a new cert/key and proceeds to distribute the results to all of the peers.

## TO-DO

### Expiration

At the moment, there is no code to handle expiring certificates. The simplest answer is to stop all Apex servers and restart which will re-seed the cluster. Some consideration as to how to handle this is being explored.

### Status

No additional code has been provided to allow monitoring of the service. Given it runs as a Docker container its easy to launch the container and send its logs (stdout) to a central logging service.

