#!/bin/sh

# define the debug routine
_DEBUG=false
DEBUG ()
{
	  $_DEBUG && $@ || :
}

if [ "$1" == "--debug" ]; then
	_DEBUG=true
	shift
fi

if [ -f "/etc/rc.d/init.d/functions" ]; then
	DEBUG echo "Detected RHEL"
	PLATFORM="RHEL"
#	. /etc/rc.d/init.d/functions 2>/dev/null
elif [ -f /etc/rc.status ] ; then
	DEBUG echo "Detected SLES"
	PLATFORM="SLES"
#	. /etc/rc.status 2>/dev/null
else
	echo "Detected unsupported platform"
	exit 1
fi

# determine the path to the script in a POSIX-compliant manner
SCRIPT_PATH=`dirname "$0"`
SCRIPT_PATH=`eval "cd \"$SCRIPT_PATH\" && pwd"`
DEBUG echo "SCRIPT_PATH=$SCRIPT_PATH"
PIDFILE="${SCRIPT_PATH}/jsonListener.pid"
LOGFILE="${SCRIPT_PATH}/jsonListener.nohup.log"
PRODUCT_NAME="IBM Informix JSON Listener"
MAINCLASS="com.ibm.nosql.informix.server.ListenerCLI"

# Example parameters
# -config nosql.properties -config restListener.properties
EXTRA_ARGS="-config ${SCRIPT_PATH}/nosql.properties -config ${SCRIPT_PATH}/restListener.properties"

findJava ()
{
	# test for Java in PATH
	JAVA_BIN=`which java`
	if [ $? -ne 0 ]; then
		echo "ERROR: java could not be found in PATH";
		exit 1;
	else
		DEBUG echo "JAVA_BIN=$JAVA_BIN";
	fi
	
	# inspect the Java version
	JAVA_VERSION=`java -version 2>&1 | head -n 1 | cut -d'"' -f2`
	DEBUG echo "JAVA_VERSION=$JAVA_VERSION"
}

findListenerJar ()
{
	# find the JSON JAR
	#JAR_PATTERN='JSON_*_embed.jar'
	JAR_PATTERN='JSON_*.jar'
	JAR_COUNT=`find ${SCRIPT_PATH} -name $JAR_PATTERN | wc -l`
	if [ $JAR_COUNT -lt 1 ]; then
		echo "ERROR: Unable to locate JSON JAR";
		exit 1;
	elif [ $JAR_COUNT -gt 1 ]; then
		LISTENER_JAR=`find ${SCRIPT_PATH} -name $JAR_PATTERN | tail -n 1`
		echo "WARNING: More than one JSON Listener JAR was found. Using $LISTENER_JAR";
	else
		LISTENER_JAR=`find ${SCRIPT_PATH} -name $JAR_PATTERN | tail -n 1`
		DEBUG echo "LISTENER_JAR=$LISTENER_JAR"
	fi
	
	CLASSPATH="${LISTENER_JAR}:${SCRIPT_PATH}/tomcat-embed-core.jar"
}

# run listener command-line interface
findJava
findListenerJar

startListener()
{
/bin/sh <<EOF
java -cp ${CLASSPATH} ${MAINCLASS} -start -daemon ${EXTRA_ARGS} <&- 1>&2 &
echo foo$!
echo `pgrep -P $$ java`
#pid=`echo $!`
#echo "foo${pid}"
EOF
}

_checkproc()
{
	# strip off arguments
	if [ "$1" == "-p" ]; then
		shift
		pid_file="$1"
		shift
	fi
	bin=`basename $1`
	if [ -z $pid_file ]; then
		pid_file="/var/run/${bin}.pid"
	fi
	DEBUG echo "pid_file=$pid_file"
	DEBUG	echo "bin=$bin"
	pid=`head -1 $pid_file 2>/dev/null`
	if [ $? -ne 0 ]; then
		DEBUG echo "could not read from pid file"
		if [ -f $pid_file ]; then
			return 102;
		else
			return 3;
		fi
	else
		DEBUG echo "pid=$pid"
		ps -p ${pid} 1>/dev/null
		if [ $? -eq 0 ]; then
			return 0;
		else
			return 1;
		fi
	fi
}

updateStatus()
{
	case "$PLATFORM" in
	'SLES')
		checkproc -p "${PIDFILE}" "${JAVA_BIN}" 1>/dev/null
		STATUS=$?
	;;
	'RHEL'|*)
		_checkproc -p "${PIDFILE}" "${JAVA_BIN}"
		STATUS=$?
	;;
	esac
}

case "$1" in
	'start')
	updateStatus
		if [ $STATUS -eq 0 ]; then
			DAEMON_PID=`head -n 1 ${PIDFILE}`
			echo "The ${PRODUCT_NAME} is already running (PID=$DAEMON_PID)"
		else
			echo "Starting the ${PRODUCT_NAME}"
			#java -cp "${JSON_JAR}:tomcat-embed-core.jar" com.ibm.nosql.informix.server.ListenerCLI $@
			#nohup java -cp ${CLASSPATH} ${MAINCLASS} -start ${EXTRA_ARGS} 2>&1 1>${LOGFILE} &
#			DAEMON_PID=`startListener` # 2>/dev/null
#			echo "DAEMON_PID=$DAEMON_PID"
#			if ps -p "${DAEMON_PID}" >/dev/null 2>&1
#			then
#				echo "The ${PRODUCT_NAME} is running"
#				echo $PID > "${PIDFILE}"
#			else
#				echo "The ${PRODUCT_NAME} did not start"
#			fi
	
			DEBUG echo "${JAVA_BIN} -cp ${CLASSPATH} ${MAINCLASS} -start -daemon ${EXTRA_ARGS} <&- &"
			${JAVA_BIN} -cp ${CLASSPATH} ${MAINCLASS} -start -daemon ${EXTRA_ARGS} <&- &
			if [ $? -eq 0 ]; then
				PID=`echo $!`
				DEBUG echo "PID=$PID"
				echo $PID > "${PIDFILE}"
			else
				echo "Unable to start"
			fi
		fi
	;;
	
	'stop')
		updateStatus
		if [ $STATUS -eq 0 ]; then
			DAEMON_PID=`head -n 1 ${PIDFILE}`
			echo "Killing the ${PRODUCT_NAME} (PID=${DAEMON_PID})"
			case "$PLATFORM" in
			'SLES')
			pkill -TERM --pidfile "${PIDFILE}"
			STATUS=$?
			;;
			'RHEL'|*)
			kill -TERM ${DAEMON_PID}
			STATUS=$?
			;;
			esac
			if [ $STATUS -eq 0 ]; then
				rm -f "${PIDFILE}" 2>/dev/null
			else
				echo "Unable to kill the ${PRODUCT_NAME}"
			fi
		elif [ $STATUS -eq 1 ]; then
			echo "The ${PRODUCT_NAME} is not running"
			rm -f "${PIDFILE}" 2>/dev/null
		elif [ $STATUS -eq 3 ]; then
			echo "The ${PRODUCT_NAME} is not running"
			DEBUG echo -e "The PIDFILE \"${PIDFILE}\" does not exist"
		else
				echo "Unsupported exit code $STATUS from checkproc"
		fi
	;;
	
	'status')
		updateStatus
		if [ $STATUS -eq 0 ]; then
			DAEMON_PID=`head -n 1 ${PIDFILE}`
			echo "The ${PRODUCT_NAME} is running (PID=${DAEMON_PID})"
		elif [ $STATUS -eq 1 ]; then
			echo "The ${PRODUCT_NAME} is not running"
			DEBUG echo "The PIDFILE referred to a process that is no longer running--removing the file"
			rm -f "${PIDFILE}" 2>/dev/null
		elif [ $STATUS -eq 3 ]; then
			echo "The ${PRODUCT_NAME} is not running"
			DEBUG echo -e "PIDFILE \"${PIDFILE}\" does not exist"
		else
				echo "Unsupported exit code $STATUS from checkproc"
		fi
	;;
	
	'restart')
		updateStatus
		if [ $STATUS -eq 0 ]; then
			$0 stop
			sleep 5
		fi
		$0 start
	;;
	
	*)
		echo "Usage: $0 { start | stop | restart | status }"
	;;
esac
exit 0

