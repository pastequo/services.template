package conf

import (
	"github.com/pastequo/libs.golang.utils/logutil"
	"github.com/spf13/viper"
)

const prefix = "xxx"

// Below all the different keys used to configure this service.
const (
	logsLevel = "LOGS_LEVEL"

	// mock repo
	mockEnvVar = "MOCK_REPO"

	// params for serial number hashing & encryption
	hashKey       = "HASH_KEY"
	encryptionKey = "ENCRYPTION_KEY"

	// params for mongo
	mongoURL        = "MONGO_URL"
	mongoUser       = "MONGO_USER"
	mongoPwd        = "MONGO_PASSWORD"
	mongoAuthSource = "MONGO_AUTHSOURCE"
)

// ParseConfiguration reads the configuration file given as parameter.
func ParseConfiguration(confFile string) {
	logger := logutil.GetDefaultLogger()

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

// MongoConf is a struct to store mongo connection information.
type MongoConf struct {
	URL        string
	User       string
	Password   string
	AuthSource string
}

// GetMongoInformation returns a MongoConf based on the configuration file.
func GetMongoInformation() *MongoConf {
	logger := logutil.GetDefaultLogger()

	logger.Debugf("mongo info: %v %v %v %v",
		viper.GetString(mongoURL),
		viper.GetString(mongoUser),
		viper.GetString(mongoPwd),
		viper.GetString(mongoAuthSource),
	)

	return &MongoConf{
		URL:        viper.GetString(mongoURL),
		User:       viper.GetString(mongoUser),
		Password:   viper.GetString(mongoPwd),
		AuthSource: viper.GetString(mongoAuthSource),
	}
}

// GetHashKey returns the key to use to hash serial numbers.
func GetHashKey() string {
	return viper.GetString(hashKey)
}

// GetEncryptionKey returns the key to use to encrypt serial numbers.
func GetEncryptionKey() string {
	return viper.GetString(encryptionKey)
}

// GetLogsLevel returns the log-level to set to the logger.
func GetLogsLevel() logutil.Level {
	logger := logutil.GetDefaultLogger()

	if !viper.IsSet(logsLevel) {
		logger.Info("log level not set, using default value: WARN")
		return logutil.WarnLevel
	}

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

	logger.Infof("unknown value '%v', returning default value: WARN", level)

	return logutil.WarnLevel
}

// UseMockRepo returns 'true' if the usecases should use the mock implementation of repositories (for test).
func UseMockRepo() bool {
	return viper.IsSet(mockEnvVar) && viper.GetInt(mockEnvVar) == 1
}
