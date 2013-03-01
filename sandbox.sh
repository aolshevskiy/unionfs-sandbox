#!/bin/bash
PROJDIR=$(realpath $(dirname $(realpath $0)))/
WORKDIR=$PROJDIR/work/
OVERLAY=${OVERLAY:-"overlay"}
OVERLAY=$WORKDIR/$OVERLAY
SANDBOX=${SANDBOX:-"sandbox"}
SANDBOX=$(realpath $WORKDIR/$SANDBOX)
SANDBOXSTAMP=$WORKDIR/.sandbox
JAVA_HOME=${SANDBOX_JAVA_HOME:-"/opt/java6"}
STRIPESDIR=$PROJDIR/stripes/
STRIPES=$WORKDIR/.stripes
env_script() {
			cat <<EOF
export JAVA_HOME=$JAVA_HOME
export PATH=$PATH
EOF
}
export JAVA_HOME=$JAVA_HOME
export PATH=$JAVA_HOME/bin:$PATH
regex_escape() {
	echo $1 | sed 's/\(\/\|\.\)/\\\1/g'
}
ESCAPED_SANDBOX=$(regex_escape $SANDBOX)
ESCAPED_JAVA_HOME=$(regex_escape $JAVA_HOME)
isinsandbox() {
	[ -f $SANDBOXSTAMP ] && return 0 || return 1
}
insandbox_guard() {
	if ! isinsandbox; then
		echo "Not in sandbox."
		exit 1
	fi
}
notinsandbox_guard() {
	if isinsandbox; then
		echo "In sandbox."
		exit 1
	fi
}
enter_sandbox() {
	touch $SANDBOXSTAMP
}
exit_sandbox() {
	rm $SANDBOXSTAMP
}
add_stripe() {
	if [ -d $WORKDIR/$1 ]; then
		echo Stripe $1 already added.
		exit 1
	fi
	mkdir $WORKDIR/$1
	cd $WORKDIR/$1
	pv $(find $STRIPESDIR -maxdepth 1 -name "$1*") | bsdtar -xf -
	[ "$2" != "true" ] && \
		grep -lrZ "\${INSTALL_DESTINATION_PREFIX}\|\${JAVA_HOME_PLACEHOLDER}" . | xargs -0 sed -i \
		-e "s/\${INSTALL_DESTINATION_PREFIX}/$ESCAPED_SANDBOX/g" \
		-e "s/\${JAVA_HOME_PLACEHOLDER}/$ESCAPED_JAVA_HOME/g"
	echo $1 >> $STRIPES
}
COMMAND=$1
shift
case $COMMAND in
	'env')
		env_script		
		;;
	'reset-env')
		cat <<EOF
. /etc/profile
. ~/.zshrc
EOF
		;;	
	'enter')
		notinsandbox_guard
		cd $WORKDIR
		ESCAPED_WORKDIR=$(regex_escape $WORKDIR)
		CURRENT_STRIPES=$(tac $STRIPES | sed -e "s/^/$ESCAPED_WORKDIR/" -e 's/$/=ro/' | paste -s -d:)
		sudo unionfs \
			-o cow,max_files=32000,allow_other \
			$OVERLAY=rw:$CURRENT_STRIPES \
			$SANDBOX
		enter_sandbox
		;;
	'exit')
		insandbox_guard
		sudo umount $SANDBOX
		cd $OVERLAY
		sudo rm -rf .unionfs
		chmod -R a+r .
		chmod -R g-w .
		find . -type d -exec chmod +x {} +
		find . -perm /u+x -exec chmod +x {} +
		chown -R siasia:users .
		grep -lrZ "$ESCAPED_SANDBOX\|$ESCAPED_JAVA_HOME" . | xargs -0 sed -i \
			-e "s/$ESCAPED_SANDBOX/\${INSTALL_DESTINATION_PREFIX}/g" \
			-e "s/$ESCAPED_JAVA_HOME/\${JAVA_HOME_PLACEHOLDER}/g"		
		exit_sandbox
		;;
	'wipe-sandbox')
		notinsandbox_guard
		rm -rf $OVERLAY
		mkdir $OVERLAY
		;;
	'create-stripe')
		notinsandbox_guard
		bsdtar -C $OVERLAY -cf - . | 7z a dummy -txz -si -so -bd | pv > $STRIPESDIR/$1.tar.xz
		;;
	'add-stripe')
		add_stripe $1
		;;
	'add-vanilla-stripe')
		add_stripe $1 true
		;;
	'remove-stripe')
		if [ ! -d $WORKDIR/$1 ]; then
			echo Stripe $1 is not added.
			exit 1
		fi
		rm -rf $WORKDIR/$1
		sed -i "/^$(regex_escape $1)\$/d" $STRIPES
		;;
	'scratch')
		;;
esac


