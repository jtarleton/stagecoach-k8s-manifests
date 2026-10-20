vcl 4.1;

# Varnish full-page cache for Drupal. Cache invalidation is tag-based:
# Drupal (purge + varnish_purger) sends BAN requests carrying a Cache-Tags
# regex, matched against the Cache-Tags header stored on each cached object.

import std;

backend drupal {
    .host = "drupal";
    .port = "8080";
    .connect_timeout = 5s;
    .first_byte_timeout = 60s;
    .between_bytes_timeout = 10s;
    .probe = {
        .url = "/healthz";
        .interval = 10s;
        .timeout = 2s;
        .window = 5;
        .threshold = 3;
    }
}

# Only pods inside the cluster may purge. Requests relayed by the edge always
# carry a multi-hop X-Forwarded-For, so they are refused below as well.
acl purgers {
    "10.42.0.0"/16;
    "127.0.0.1";
}

sub vcl_recv {
    if (req.url == "/varnish-health") {
        return (synth(200, "OK"));
    }

    if (req.method == "BAN" || req.method == "PURGE") {
        if (!client.ip ~ purgers || req.http.X-Forwarded-For ~ ",") {
            return (synth(405, "Not allowed"));
        }
        if (req.method == "PURGE") {
            return (purge);
        }
        # Cache-Tags is a pipe-separated list ("node:1|node_list"); anchor it on
        # whitespace so node:1 doesn't also ban node:10.
        if (req.http.Cache-Tags) {
            ban("obj.http.Cache-Tags ~ (^|\s)(" + req.http.Cache-Tags + ")(\s|$)");
            return (synth(200, "Ban added"));
        }
        return (synth(400, "Cache-Tags header required"));
    }

    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }
    if (req.http.Authorization) {
        return (pass);
    }
    if (req.url ~ "^/(admin|user|batch)(/|\?|$)") {
        return (pass);
    }

    # Marketing parameters don't change the page; drop them for a better hit rate.
    if (req.url ~ "[?&](utm_[a-z]+|gclid|fbclid|msclkid)=") {
        set req.url = regsuball(req.url, "(utm_[a-z]+|gclid|fbclid|msclkid)=[^&]*&?", "");
        set req.url = regsub(req.url, "[?&]+$", "");
    }

    if (req.url ~ "\.(avif|webp|png|jpe?g|gif|svg|ico|woff2?|ttf|otf|css|js|map|pdf|txt)(\?.*)?$") {
        unset req.http.Cookie;
        return (hash);
    }

    # Keep only Drupal session cookies; a session means a personalised page.
    if (req.http.Cookie) {
        set req.http.Cookie = ";" + req.http.Cookie;
        set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");
        set req.http.Cookie = regsuball(req.http.Cookie, ";(S?SESS[a-z0-9]+|NO_CACHE)=", "; \1=");
        set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
        set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");
        if (req.http.Cookie == "") {
            unset req.http.Cookie;
        } else {
            return (pass);
        }
    }

    return (hash);
}

sub vcl_hash {
    hash_data(req.http.X-Forwarded-Proto);
}

sub vcl_backend_response {
    if (bereq.url ~ "\.(avif|webp|png|jpe?g|gif|svg|ico|woff2?|ttf|otf|css|js|map|pdf|txt)(\?.*)?$") {
        unset beresp.http.Set-Cookie;
        # Browsers may keep assets longer; Varnish memory is better spent on pages.
        if (beresp.ttl > 1d) {
            set beresp.ttl = 1d;
        }
    }

    # Keep serving the stale copy if a background refresh hits a backend error.
    if (beresp.status >= 500 && bereq.is_bgfetch) {
        return (abandon);
    }

    # Serve stale content while refreshing, and while the backend is down.
    set beresp.grace = 6h;
}

sub vcl_deliver {
    # Cache metadata is for Varnish only.
    unset resp.http.Cache-Tags;
    unset resp.http.X-Drupal-Cache-Tags;
    unset resp.http.X-Drupal-Cache-Contexts;
    unset resp.http.X-Drupal-Cache-Max-Age;
    unset resp.http.X-Generator;
    unset resp.http.X-Varnish;
    unset resp.http.Via;

    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
}
