<?php 

	class SchedulerLinuxLauncher implements SchedulerLauncherInterface, SchedulerConfiguratorAwareInterface, SchedulerLoggerAwareInterface
	{
		private $configurator;
		private $logger;
		private $wrapperScript = "/usr/local/php52/bin/php /***REMOVED***/lib/php5/***REMOVED***/projects/intranet/***REMOVED***/offspring/scheduler/SchedulerTaskWrapper.php";
		private $logging = FALSE;
		
		public function setConfigurator(SchedulerConfiguratorInterface $configurator)
		{
			$this->configurator = $configurator;
		}
				
		public function setLogger(SchedulerLoggerInterface $logger)
		{
			$this->logger = $logger;
			$this->logging = TRUE;
		}
				
		public function launchTasks($timeStamp)
		{
			$taskIds = $this->configurator->getTaskList($timeStamp);
			if (count($taskIds) == 0)
			{
				$this->log("LAUNCHER", "NOTE", "", sprintf("No tasks to execute for timestamp '%s' (%s)", $timeStamp, date("Y-m-d H:i:s", $timeStamp)));
			}
			else
			{
				$this->log("LAUNCHER", "NOTE", "", sprintf("Executing tasks for timestamp '%s' (%s): %s", $timeStamp, date("Y-m-d H:i:s", $timeStamp), implode(",", $taskIds)));
			}
				
			$this->configurator->refresh();
			for ($i=0;$i<count($taskIds);$i++)
			{
				$currentTaskCount = $this->getTaskCount($taskIds[$i]);
				$maxTaskCount = $this->configurator->getMaxTaskInstanceCount($taskIds[$i]);
				if ($currentTaskCount >= $maxTaskCount)
				{
					$this->log("LAUNCHER", "SKIP_EXECUTE", $taskIds[$i], sprintf("Task #%s has reached maximum instance count (%s), skipping", $taskIds[$i], $maxTaskCount));
					continue;
				}

				$this->log("LAUNCHER", "EXECUTE", $taskIds[$i], sprintf("Launching task #%s", $taskIds[$i]));								
				$runId = md5(rand().$timeStamp.$i.microtime());
				exec(sprintf("%s %s %d %d > /dev/null &", $this->wrapperScript, $runId, $taskIds[$i], $timeStamp));
			}
		}
		
		public function killTask($runId)
		{		
			exec(sprintf("kill `ps aux | grep '%s' | awk '{ print $2 }' | grep '%d'`", $this->wrapperScript, $runId));
			if ($this->isTaskRunning($runId)) 
			{
				$this->log("LAUNCHER", "KILL", $runId, sprintf("Successfully killed task #%s", $runId)); 
				return FALSE; 
			}
			else
			{
				$this->log("LAUNCHER", "KILL", $runId, sprintf("Failed to kill task #%s", $runId));
				return TRUE;
			}
			
		}
	
		public function isTaskRunning($runId)
		{
			if (exec(sprintf("ps aux | grep '%s' | awk '{ print $2 }' | grep '%d'", $this->wrapperScript, $runId)) == $runId) return TRUE;
			else return FALSE;
		}

		public function getTaskCount($taskId)
		{
			$taskNum = exec(sprintf("ps aux | grep '%s [a-zA-Z0-9_-]\+ %d [0-9]\+' | wc -l", $this->wrapperScript, $taskId));
			return $taskNum;
		}
		private function log($component, $type, $task, $message)
		{
			if ($this->logging)
			{
				$event = new SchedulerEvent();
				$event->setTask($task);
				$event->setComponent($component);
				$event->setType($type);
				$event->setMessage($message);
				$this->logger->log($event);				
			}
		}
	}

?>
