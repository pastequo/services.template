package conf

import (
	"github.com/pastequo/libs.golang.utils/logutil"
	"github.com/spf13/viper"
)

const prefix = "xxx"

// Below all the different keys used to configure this service.
const (
	logsLevel = "LOGS_LEVEL"
)

// ParseConfiguration reads the configuration file given as parameter.
func ParseConfiguration(confFile string) {
	logger := logutil.GetDefaultLogger()

	setDefault()

	viper.SetEnvPrefix(prefix)
	viper.AutomaticEnv() // read in environment variables that match

	if len(confFile) > 0 {
		viper.SetConfigFile(confFile)

		err := viper.ReadInConfig()
		if err != nil {
			logger.WithError(err).Errorf("failed to read config file %v", confFile)
		} else {
			logger.Infof("using config file: %v", viper.ConfigFileUsed())
		}
	}
}

func setDefault() {
	viper.SetDefault(logsLevel, "WARN")
}

// GetLogsLevel returns the log-level to set to the logger.
func GetLogsLevel() logutil.Level {
	logger := logutil.GetDefaultLogger()

	level := viper.GetString(logsLevel)
	switch level {
	case "TRACE":
		return logutil.TraceLevel
	case "DEBUG":
		return logutil.DebugLevel
	case "INFO":
		return logutil.InfoLevel
	case "WARN":
		return logutil.WarnLevel
	case "ERROR":
		return logutil.ErrorLevel
	}

	logger.Infof("unknown value '%v', will use WARN value", level)

	return logutil.WarnLevel
}
