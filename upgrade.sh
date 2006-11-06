#! /bin/sh

if [ $# -ne 2 ] ; then
    echo "Usage: $0 sourcedir destdir"
    exit 1
fi
sourcedir=$1
destdir=$2

if [ ! -d "$sourcedir" -o ! -d "$destdir" ] ; then
    echo "No such file or directory"
fi

ACTION_PREFIX=""
#echo

ask(){
    typeset question=$1
    typeset answer=r
    while [ $answer = 'r' ] ; do
	echo -n "$question "
	read answer
	case $answer in
	    [Yy])
		answer=1
		;;
	    [Nn])
		answer=0
		;;
	    *)
		answer=r
	esac
    done
    return $answer
}

overwrite() {
    typeset sourcefile=$1
    typeset destfile=$2
    typeset destdir=`dirname $destfile`
    if [ ! -d "$destdir" ] ; then
	$ACTION_PREFIX mkdir -vp $destdir
    fi
    $ACTION_PREFIX cp -v $sourcefile $destfile
}

mergefile() {
    typeset sourcefile=$1
    typeset destfile=$2
    if [ ! -f $destfile ] ; then
	ask "Destination does not exist. Copy $sourcefile as $destfile?"
	if [ $? -eq 1 ] ; then
	    overwrite $sourcefile $destfile
	fi
	return 0
    fi
    diff -ubq $destfile $sourcefile > /dev/null
    if [ $? -eq 1 ] ; then
	ask "Files $sourcefile and $destfile differ. View difference?"
	if [ $? -eq 1 ] ; then
	    $ACTION_PREFIX diff -rub $destfile $sourcefile | less
	fi
	ask "Overwrite changes?"
	if [ $? -eq 1 ] ; then
	    overwrite $sourcefile $destfile
	fi
    fi
}

for filename in  `cd $sourcedir && find . -type f ` ; do
    mergefile $sourcedir/$filename $destdir/$filename
done
