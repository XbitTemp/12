/* SPDX-License-Identifier: MIT
 *
 * AwgChain pack 55: five more calls over the pipe that already carries the
 * chain status from pack 54.
 *
 *   101 read the boxes of one tunnel
 *   102 write the boxes of one tunnel
 *   103 read the settings of the program
 *   104 write the settings of the program
 *   105 lift the lock right now
 */

package manager

import (
	"encoding/gob"
	"log"
)

const (
	ChainSettingsGetMethodType MethodType = 101
	ChainSettingsSetMethodType MethodType = 102
	ChainGlobalGetMethodType   MethodType = 103
	ChainGlobalSetMethodType   MethodType = 104
	ChainLiftLockMethodType    MethodType = 105
)

//
// The service side.
//

func (s *ManagerService) chainServeSettingsGet(decoder *gob.Decoder, encoder *gob.Encoder) error {
	var name string
	err := decoder.Decode(&name)
	if err != nil {
		return err
	}

	err = encoder.Encode(ChainSettingsFor(name))
	if err != nil {
		return err
	}

	return encoder.Encode(errToString(nil))
}

func (s *ManagerService) chainServeSettingsSet(decoder *gob.Decoder, encoder *gob.Encoder) error {
	var name string
	err := decoder.Decode(&name)
	if err != nil {
		return err
	}

	var settings ChainTunnelSettings
	err = decoder.Decode(&settings)
	if err != nil {
		return err
	}

	saveErr := ChainSettingsSave(name, settings)
	if saveErr == nil {
		s.chainSettingsApplyNow(name)
		log.Printf("[AwgChain] The settings of %s are saved: kill switch %v, IPv6 blocked %v, local network %v", name, settings.KillSwitch, settings.BlockIPv6, settings.AllowLAN)
	}

	return encoder.Encode(errToString(saveErr))
}

func (s *ManagerService) chainServeGlobalGet(encoder *gob.Encoder) error {
	err := encoder.Encode(ChainGlobal())
	if err != nil {
		return err
	}

	return encoder.Encode(errToString(nil))
}

func (s *ManagerService) chainServeGlobalSet(decoder *gob.Decoder, encoder *gob.Encoder) error {
	var global ChainGlobalSettings
	err := decoder.Decode(&global)
	if err != nil {
		return err
	}

	saveErr := ChainGlobalSave(global)
	if saveErr == nil {
		log.Printf("[AwgChain] The program settings are saved: raise %v (%s), lift the lock on quit %v", global.RaiseOnStart, global.RaiseTunnel, global.LiftLockOnQuit)
	}

	return encoder.Encode(errToString(saveErr))
}

func (s *ManagerService) chainServeLiftLock(encoder *gob.Encoder) error {
	chainDisarmLockInProc()
	chainDropIPv6Block()
	log.Printf("[AwgChain] The lock is lifted because the program is closing")

	return encoder.Encode(errToString(nil))
}

//
// The interface side.
//

func IPCClientChainSettings(name string) (ChainTunnelSettings, error) {
	var settings ChainTunnelSettings

	rpcMutex.Lock()
	defer rpcMutex.Unlock()

	err := rpcEncoder.Encode(ChainSettingsGetMethodType)
	if err != nil {
		return settings, err
	}
	err = rpcEncoder.Encode(name)
	if err != nil {
		return settings, err
	}
	err = rpcDecoder.Decode(&settings)
	if err != nil {
		return settings, err
	}

	return settings, rpcDecodeError()
}

func IPCClientChainSettingsSave(name string, settings ChainTunnelSettings) error {
	rpcMutex.Lock()
	defer rpcMutex.Unlock()

	err := rpcEncoder.Encode(ChainSettingsSetMethodType)
	if err != nil {
		return err
	}
	err = rpcEncoder.Encode(name)
	if err != nil {
		return err
	}
	err = rpcEncoder.Encode(settings)
	if err != nil {
		return err
	}

	return rpcDecodeError()
}

func IPCClientChainGlobal() (ChainGlobalSettings, error) {
	var global ChainGlobalSettings

	rpcMutex.Lock()
	defer rpcMutex.Unlock()

	err := rpcEncoder.Encode(ChainGlobalGetMethodType)
	if err != nil {
		return global, err
	}
	err = rpcDecoder.Decode(&global)
	if err != nil {
		return global, err
	}

	return global, rpcDecodeError()
}

func IPCClientChainGlobalSave(global ChainGlobalSettings) error {
	rpcMutex.Lock()
	defer rpcMutex.Unlock()

	err := rpcEncoder.Encode(ChainGlobalSetMethodType)
	if err != nil {
		return err
	}
	err = rpcEncoder.Encode(global)
	if err != nil {
		return err
	}

	return rpcDecodeError()
}

func IPCClientChainLiftLock() error {
	rpcMutex.Lock()
	defer rpcMutex.Unlock()

	err := rpcEncoder.Encode(ChainLiftLockMethodType)
	if err != nil {
		return err
	}

	return rpcDecodeError()
}
