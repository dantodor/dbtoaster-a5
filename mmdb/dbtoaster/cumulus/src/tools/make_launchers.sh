#!/bin/bash

BASEDIR=`dirname $0`
LAUNCHERS=$BASEDIR/launchers.list

for i in $(awk '{print $1}' $LAUNCHERS); do
if [ "bin/$i.sh" -ot "$0" -o "bin/$i.sh" -ot "$LAUNCHERS" ] ; then
echo Creating bin/$i.sh
FORMAT=$(grep "^$i" $LAUNCHERS | awk '{print $3}');
if [ "$FORMAT" = "java" ] ; then 
EXEC_STRING="java -cp --CLASSPATH-- --CLASS-- \$(dirname \$0)/../local.properties \$*"
elif [ "$FORMAT" = "jruby" ] ; then 
EXEC_STRING="jruby -J-cp --CLASSPATH-- -e \"include Java;require '--CLASS--';\" -- \$*"
fi

EXEC_CMD=$(echo "$EXEC_STRING" | 
  sed "
    s#--CLASSPATH--#$1#; 
    s#--CLASS--#$(grep "^$i" $LAUNCHERS | awk '{print $2}')#;
  ");
cat > bin/$i.sh << EOF
################# BEGIN AUTOGENERATED LAUNCHER SCRIPT #################
echo ========================
echo "$(echo $EXEC_CMD | sed 's#"#\\"#g' | cat)"
echo ========================
$EXEC_CMD
################# END AUTOGENERATED LAUNCHER SCRIPT #################
EOF
chmod +x bin/$i.sh
fi
done