## OTC ACME DNS challenge automatization for certbot

Bash hook for [certbot][0] to automate [ACME][1] (IETF [RFC 8555][2]) DNS-01 challenging with [Open Telekom Cloud][3] (OTC) [DNS][4] Service. [Let's Encrypt][5] is the most popular public ACME CA. [Telesec][6] is planning to provide an ACME service.

[0]: https://certbot.eff.org/
[1]: https://en.wikipedia.org/wiki/Automated_Certificate_Management_Environment
[2]: https://datatracker.ietf.org/doc/html/rfc8555
[3]: https://open-telekom-cloud.com/
[4]: https://docs.otc.t-systems.com/dns/
[5]: https://letsencrypt.org/
[6]: https://www.telesec.de/

### Quick Start

To obtain a certificate for your OTC hosted domain right away, follow these steps.

1. **Install certbot.** There are many ways to install certbot, depending on your distribution and preference. Please follow instructions on https://certbot.eff.org/

2. **Install hook.** To authenticate your OTC domain against an ACME CA like Let's Encrypt using the DNS challenge mechanism, you will need to update your domain DNS dynamically. The hook script automatizes this process for you. To use it, download the `otc-certbot-hook.sh` and `.otc-certbot-hook.auth` files and place them into a directory of your choice. Ensure that you have a recent [`curl`][10] and [`jq`][11] as well on your system.

[10]: https://curl.se/
[11]: https://stedolan.github.io/jq/

3. **Set up hook.** You need to provide some OTC credentials to the hook. To do so, edit the `.otc-certbot-hook.auth` file. It's commented.

4. **Run certbot.** To obtain your certificate, run certbot in manual mode, setup to use the OTC hook you just downloaded. For detailed instructions on how to use certbot, please refer to the  certbot manual. A typical use of certbot is listed below. Note that the hook may wait up to one minute to be sure that the challenge was correctly published. 

```bash
certbot --manual --text --preferred-challenges dns \
        --manual-auth-hook ./otc-certbot-hook.sh \
        --manual-cleanup-hook ./otc-certbot-hook.sh \
        -d "YOUR.DOMAIN.TLD" certonly
```  

### TODO

- [ ] OTC AK/SK authentication support
- [ ] DNS Zone nesting support
- [ ] Multiple {OTC_ROOT_ZONES}

Best way seems a portable binary that encapsulates the OTC DNS dealing.

```bash
[~]> acme-otc --help
An ACME DNS-01 challenge handler for OTC.
Usage: acme-otc [-s|-d] -n fqdn -t challenge

# Publish ACME challenge for YOUR.DOMAIN.TLD
[~]> acme-otc [--set] --fqdn YOUR.DOMAIN.TLD --token bslb8t...BokMyg
# Delete ACME challenge for YOUR.DOMAIN.TLD
[~]> acme-otc --delete --fqdn YOUR.DOMAIN.TLD --token bslb8t...BokMyg
```

There is i.a. [LEGO][20] which supports OTC but doesn't support AK/SK and zone nesting.

[20]: https://github.com/go-acme/lego

### Contribution

You are welcome! Please do not hesitate to contact us with any improvements of this work. All work should be licensed under MIT license or compatible.
