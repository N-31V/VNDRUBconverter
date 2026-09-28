# T-Bank TLS trust anchor

`russian_trusted_root_ca.pem` is the RSA Russian Trusted Root CA. It is used
only by `TbankHttpClient` for `https://www.tbank.ru:443`; redirects are disabled.
The system trust store and other HTTP clients are unchanged. Certificate chain,
hostname and expiry checks remain enabled. The server supplies its intermediate
certificate, so only the root is bundled.

Downloaded over verified HTTPS on 2026-09-28 from the bank's official instructions:

- https://status.tbank-online.com/certificates/
- https://status.tbank-online.com/api-setup/
- https://help-static2.tbank-online.com/certs/%D0%90ndroid_russian_trusted_root_ca.cer

SHA-256 certificate fingerprint (DER):

`D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31`

Valid from 2022-03-01 until 2032-02-27. If the bank changes its CA, obtain the new
root from its official HTTPS distribution, verify the fingerprint and live
chain, replace the asset and rebuild. Do not disable certificate verification.
