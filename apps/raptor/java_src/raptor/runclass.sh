java -XX:+UseConcMarkSweepGC -XX:+UseParNewGC -XX:CMSInitiatingOccupancyFraction=70 -server -Dcom.sun.management.jmxremote -Djava.library.path=/usr/local/lib:/usr/local/BerkeleyDB.4.8/lib -Xmx2048m -Dfile.encoding=UTF-8 -cp .:./bin:lib/* raptor.$*
