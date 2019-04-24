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
