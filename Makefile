#
#
#
# Bootstrap Makefile


VPATH=.
PROGNAME=chilimoon
MAKE=make
PREFIX=/usr
CONFIGDIR=/etc/chilimoon
INSTALL_DIR=`which install` -c
INSTALL_DATA = `which cp`
INSTALL_DATA_R = `which cp` -r

PIKE_SRC_DIRS="../pike"

OS=`uname -srm|sed -e 's/ /-/g'|tr '[A-Z]' '[a-z]'|tr '/' '_'`

all:
	@echo "###############################################"
	@echo "###                                         ###"
	@echo "### Type make install to install ChiliMoon. ###"
	@echo "###                                         ###"
	@echo "### To make Java Servlets, type make java.  ###"
	@echo "###                                         ###"
	@echo "###############################################"

install : pike_version_test install_dirs install_datas config 

	
pike_version_test :
	VERSION=OK;\
	CONTINU=0;\
	if [ `which pike` ] ; then\
	echo TESTING PIKE VERSION;\
	echo Current Pike Version is `pike --dumpversion`;\
	PIKE_VERSION=`pike --dumpversion`;\
	IFS=.; set $${PIKE_VERSION}; IFS=' ';\
	if [ "$$2" == "7" ] ; then\
	echo Pike version Checked out OK;\
	else\
	echo Found Older Version of Pike;\
	echo Do you want to continu using old Version?;\
	while [[ "$${CONTINU}" != "Y" && "$${CONTINU}" != "N" ]] ; do\
        read CONTINU;\
	done;\
	if [ "$${CONTINU}" == "Y" ] ; then\
	VERSION=OK;\
	else\
	VERSION=NOK;\
	fi\
	fi\
	else\
	echo Pike not found.;\
	VERSION=NOK;\
	fi;\
	if [ "$${VERSION}" == "NOK" ] ; then\
	for i in ${PIKE_SRC_DIRS} ; do\
	cd $${i}/ && make;\
	done;\
	fi\

install_dirs :
	$(INSTALL_DIR) -dD $(PREFIX)/$(PROGNAME);
	$(INSTALL_DIR) -dD $(PREFIX)/$(PROGNAME)/server;
	$(INSTALL_DIR) -dD $(PREFIX)/$(PROGNAME)/local;

install_datas :
	$(INSTALL_DATA_R) server 	$(PREFIX)/$(PROGNAME)/;
	$(INSTALL_DATA_R) local 	$(PREFIX)/$(PROGNAME)/;
	$(INSTALL_DATA)   GPL   	$(PREFIX)/$(PROGNAME)/;
	$(INSTALL_DATA)   COPYING   	$(PREFIX)/$(PROGNAME)/;
	$(INSTALL_DATA)   README   	$(PREFIX)/$(PROGNAME)/;
	$(INSTALL_DATA)   Manifest   	$(PREFIX)/$(PROGNAME)/;
	$(INSTALL_DATA)   start  	$(PREFIX)/$(PROGNAME)/;

config_test: 
	if [ -f /etc/chilimoon/_admininterface/settings/admin_uid ] ; then\
	: ;\
	else\
	make config;\
	fi
	
config :
	cd $(PREFIX)/$(PROGNAME)/server/mysql;\
	./lnmysql.sh;
	pike $(PREFIX)/$(PROGNAME)/server/bin/create_configif.pike -d $(CONFIGDIR)

.phony: install
