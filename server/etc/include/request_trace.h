// -*- pike -*-
//
// Some stuff to do logging of a request through the server.
//
// $Id: request_trace.h,v 1.16 2008/09/26 10:20:38 mast Exp $

#ifndef REQUEST_TRACE_H
#define REQUEST_TRACE_H

#include <roxen.h>
#include <module.h>

// Note that TRACE_ENTER (and TRACE_LEAVE) takes message strings
// in plain text. Messages are preferably a single line, and they
// should not end with period and/or newline.
//
//
// Roxen 5.0 compatibility notice:
//
//   Pre-5.0 TRACE_ENTER and TRACE_LEAVE allowed html markup to pass
//   through unquoted into the Resolve Path wizard page, but since the
//   ultimate destination may not be a web page at all this capability
//   has been removed. The Resolve Path wizard will now quote all
//   strings instead.

#ifdef REQUEST_TRACE

# define TRACE_ENTER(A,B) Roxen->trace_enter (id, (A), (B))
# define TRACE_LEAVE(A) Roxen->trace_leave (id, (A))

#else

# define TRACE_ENTER(A,B) do{ \
    function(string,mixed ...:void) _trace_enter; \
    if(id && \
       (_trace_enter = \
        [function(string,mixed ...:void)]([mapping(string:mixed)]id->misc)-> \
          trace_enter)) \
      _trace_enter((A), (B)); \
  }while(0)

# define TRACE_LEAVE(A) do{ \
    function(string:void) _trace_leave; \
    if(id && \
       (_trace_leave = \
        [function(string:void)]([mapping(string:mixed)]id->misc)-> \
          trace_leave)) \
      _trace_leave(A); \
  }while(0)

#endif

// SIMPLE_TRACE_ENTER and SIMPLE_TRACE_LEAVE are simpler variants of
// the above macros since they handle sprintf style format lists. Note
// the reversed argument order in SIMPLE_TRACE_ENTER compared to
// TRACE_ENTER.

#define SIMPLE_TRACE_ENTER(OBJ, MSG...) do {				\
    array _msg_arr_;							\
    TRACE_ENTER (  (_msg_arr_ = ({MSG}),				\
		    sizeof (_msg_arr_) > 1 ? sprintf (@_msg_arr_) :	\
		    (sizeof (_msg_arr_) ? _msg_arr_[0] : "")),		\
		 (OBJ));						\
  } while (0)

#define SIMPLE_TRACE_LEAVE(MSG...) do {					\
    array _msg_arr_;							\
    TRACE_LEAVE (  (_msg_arr_ = ({MSG}),				\
		    sizeof (_msg_arr_) > 1 ? sprintf (@_msg_arr_) :	\
		    (sizeof (_msg_arr_) ? _msg_arr_[0] : "")));		\
  } while (0)

// The following variant should be used inside RXML.Frame callbacks
// such as do_enter. In addition to the request trace, it does rxml
// debug logging which is activated with the DEBUG define in
// combination with the magic _debug_ tag argument or the RXML_VERBOSE
// or RXML_REQUEST_VERBOSE defines.

#define TAG_TRACE_ENTER(MSG...) do {					\
    array _msg_arr_;							\
    string _msg_;							\
    TRACE_ENTER ("tag <" + (tag && tag->name) + "> " +		\
		   (_msg_arr_ = ({MSG}),				\
		    _msg_ = sizeof (_msg_arr_) > 1 ? sprintf (@_msg_arr_) : \
		    (sizeof (_msg_arr_) ? _msg_arr_[0] : "")),		\
		 tag);							\
    DO_IF_DEBUG (							\
      if (TAG_DEBUG_TEST (flags & RXML.FLAG_DEBUG))			\
	tag_debug ("%O:   %s\n", this_object(),				\
		   _msg_ ||						\
		   (_msg_arr_ = ({MSG}),				\
		    sizeof (_msg_arr_) > 1 ? sprintf (@_msg_arr_) :	\
		    (sizeof (_msg_arr_) ? _msg_arr_[0] : "")));		\
    );									\
  } while (0)

#define TAG_TRACE_LEAVE(MSG...) do {					\
    array _msg_arr_;							\
    string _msg_;							\
    TRACE_LEAVE ((_msg_arr_ = ({MSG}),					\
		  _msg_ = sizeof (_msg_arr_) > 1 ? sprintf (@_msg_arr_) : \
		  (sizeof (_msg_arr_) ? _msg_arr_[0] : "")));		\
    DO_IF_DEBUG (							\
      if (TAG_DEBUG_TEST (flags & RXML.FLAG_DEBUG)) {			\
	if (!_msg_) {							\
	  _msg_arr_ = ({MSG});						\
	  _msg_ =							\
	    sizeof (_msg_arr_) > 1 ? sprintf (@_msg_arr_) :		\
	    (sizeof (_msg_arr_) ? _msg_arr_[0] : "");			\
	}								\
	if (sizeof (_msg_)) tag_debug ("%O:   %s\n", this_object(), _msg_); \
      }									\
    );									\
  } while (0)

#ifdef AVERAGE_PROFILING
#define PROF_ENTER(X,Y) id->conf->avg_prof_enter( X, Y, id )
#define PROF_LEAVE(X,Y) id->conf->avg_prof_leave( X, Y, id )
#define COND_PROF_ENTER(X,Y,Z) if(X)PROF_ENTER(Y,Z)
#define COND_PROF_LEAVE(X,Y,Z) if(X)PROF_LEAVE(Y,Z)
#else
#define PROF_ENTER(X,Y)
#define PROF_LEAVE(X,Y)
#define COND_PROF_ENTER(X,Y,Z)
#define COND_PROF_LEAVE(X,Y,Z)
#endif

#endif	// !REQUEST_TRACE_H
