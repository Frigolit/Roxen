/*
 * $Id: Defvar.java,v 1.1 2004/05/31 11:48:51 _cvs_dirix Exp $
 *
 */

package com.chilimoon.chilimoon;

class Defvar {

  String var, name, doc;
  Object value;
  int type;

  Defvar(String _var, Object _value, String _name, int _type, String _doc)
  {
    var = _var;
    value = _value;
    name = _name;
    type = _type;
    doc = _doc;
  }

}


