#!bin/pike

// $Id: create_testcert.pike,v 1.2 2002/06/05 17:15:06 nilsson Exp $

import Standards.ASN1.Types;

int main(int argc, array(string) argv)
{
  mapping attrs =
  ([ "countryName"		: "SE",
//     "stateOrProvinceName"	: "",
//     "localityName"		: "",
//     "organizationName"	: "",
//     "organizationUnitName"	: "",
     "commonName"		: "*" ]);

  int key_size = 1024;		// Key size (bits)

  int ttl = 1000;		// Time to live (days)

  array name = ({ });
  if (attrs->countryName)
    name += ({ (["countryName":asn1_printable_string(attrs->countryName)]) });
  foreach( ({ "stateOrProvinceName", "localityName", "organizationName",
	      "organizationUnitName", "commonName" }), string attr)
  {
    if (attrs[attr])
      /* UTF8String is the recommended type. But it seems that
       * netscape can't handle that. So when PrintableString doesn't
       * suffice, we use latin1 but call it TeletexString (since at
       * least netscape expects things that way). */
      name += ({ ([ attr : (asn1_printable_valid (attrs[attr]) ?
			    asn1_printable_string :
			    asn1_broken_teletex_string)
		    (attrs[attr]) ]) });
  }

  object rsa = Crypto.rsa();
  rsa->generate_key( key_size,
                     Crypto.randomness.reasonably_random()->read );
  /* Create a plain X.509 v1 certificate, without any extensions */
  string cert = Tools.X509
    .make_selfsigned_rsa_certificate(rsa, 24 * 3600 * ttl,name);

  string pem_cert = Tools.PEM.simple_build_pem("CERTIFICATE", cert);
  string key = Tools.PEM.simple_build_pem("RSA PRIVATE KEY",
                                          Standards.PKCS.RSA.private_key(rsa));

  if(file_stat("demo_certificate.pem"))
    write("Overwriting existing demo SSL certificate.\n");

  mixed err =
    catch( Stdio.write_file("demo_certificate.pem", pem_cert + key) );
 
  if( !err )
    write("Demo SSL certificate successfully created.\n");
  else
  {
    werror("Failed to write demo SSL certificate."
	   " Disc full or wrong permissions?\n");
    return 1;
  }

  return 0;
}
