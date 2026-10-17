def socks_inbound($tag; $listen; $port; $username; $password; $udp; $udp_ip):
    {
        tag: $tag,
        listen: $listen,
        port: $port,
        protocol: "socks",
        settings: ({
            auth: "password",
            accounts: [{user: $username, pass: $password}],
            udp: $udp
        } + (if $udp_ip == "" then {} else {ip: $udp_ip} end))
    };

{
    log: {
        access: $access,
        error: $error,
        loglevel: $loglevel
    },
    inbounds: ([
        socks_inbound($tag; $listen; $port; $username; $password; $udp; $udp_ip)
    ] + if $ipv4_enabled then [
        socks_inbound(
            "socks5-ipv4-in";
            $ipv4_listen;
            $ipv4_port;
            $username;
            $password;
            $ipv4_udp;
            $ipv4_udp_ip
        )
    ] else [] end),
    outbounds: ([{
        tag: "random-ipv6",
        protocol: "freedom",
        sendThrough: $pool,
        settings: {domainStrategy: "UseIP"}
    }] + if $ipv4_enabled then [{
        tag: "ipv4-direct",
        protocol: "freedom",
        sendThrough: "0.0.0.0",
        settings: {domainStrategy: "UseIPv4"},
        streamSettings: {
            sockopt: {domainStrategy: "UseIPv4"}
        }
    }] else [] end)
} + if $ipv4_enabled then {
    routing: {
        rules: [{
            type: "field",
            inboundTag: ["socks5-ipv4-in"],
            outboundTag: "ipv4-direct"
        }]
    }
} else {} end
