// $Id: roxen.h,v 1.18 2000/09/24 13:35:51 nilsson Exp $
// -*- Pike -*-

#ifndef _ROXEN_H_

#define _ROXEN_H_
#include <config.h>
#define HOST_TO_IP 'H'
#define IP_TO_HOST 'I'

#define perror	roxen_perror

// Localization support

#ifndef __LOCALEOBJECT
#ifdef IN_ROXEN
#define __LOCALEOBJECT locale
#else /* !IN_ROXEN */
#define __LOCALEOBJECT roxen.locale
#endif /* IN_ROXEN */
#endif /* !__LOCALEOBJECT */

#ifndef _STR_LOCALE
#define _STR_LOCALE(X, Y, Z)	\
    (Locale.translate(X, __LOCALEOBJECT->get(), Y, Z))
#endif /* !_STR_LOCALE */

#ifndef _DEF_LOCALE
#define _DEF_LOCALE(X, Y, Z)	\
    ([string](mixed)Locale.DeferredLocale(X, GETLOCLANG, Y, Z))
#endif /* !_DEF_LOCALE */

#ifndef USE_DEFERRED_LOCALE
#define USE_DEFERRED_LOCALE	\
    static local inline string GETLOCLANG() { \
      return __LOCALEOBJECT->get(); \
    }
#endif /* !USE_DEFERRED_LOCALE */

#ifndef _LOCALE_FUN
#define _LOCALE_FUN(X, Y, Z)	\
    (Locale.call(X, __LOCALEOBJECT->get(), Y, Z))
#endif /* !_LOCALE_FUN */


#endif  /* !_ROXEN_H_ */
