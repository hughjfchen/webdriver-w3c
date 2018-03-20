{- |
Module      : Web.Api.WebDriver.Helpers
Description : Higher level WebDriver utilities.
Copyright   : 2018, Automattic, Inc.
License     : GPL-3
Maintainer  : Nathan Bloomfield (nbloomf@gmail.com)
Stability   : experimental
Portability : POSIX
-}

module Web.Api.WebDriver.Helpers (
  -- * Running Sessions
    cleanupOnError
  , runIsolated
  , runSuites
  , debugSuites

  -- * Secrets
  , stashCookies
  , loadCookies
  , writeCookieFile
  , readCookieFile

  -- * Actions
  , press
  , typeString
  ) where

import qualified Data.Aeson as Aeson (encode)

import Web.Api.Http
import Web.Api.WebDriver.Monad
import Web.Api.WebDriver.Types
import Web.Api.WebDriver.Types.Keyboard
import Web.Api.WebDriver.Endpoints



-- | If a WebDriver session ends without issuing a delete session command, then the server keeps its session state alive. `cleanupOnError` catches errors and ensures that a `deleteSession` request is sent.
cleanupOnError
  :: (Effectful m)
  => WebDriver m a -- ^ `WebDriver` session that may throw errors
  -> WebDriver m a
cleanupOnError x = catchError x (\e -> deleteSession >> throwError e)


-- | Run a WebDriver computation in an isolated browser session. Uses `cleanupOnError` to ensure the session is deleted on the server.
runIsolated
  :: (Effectful m)
  => Capabilities
  -> WebDriver m a
  -> WebDriver m ()
runIsolated caps theSession = cleanupOnError $ do
  session_id <- newSession caps
  getState >>= (putState . updateClientState (setSessionId (Just session_id)))
  theSession
  deleteSession
  getState >>= (putState . updateClientState (setSessionId Nothing))


-- | Run a list of `TestTree`s, throwing away the result.
runSuites
  :: (Effectful m)
  => WebDriverConfig
  -> Capabilities
  -> WebDriver m () -- ^ Setup: run once before the suite (for logging in, etc.)
  -> WebDriver m () -- ^ Teardown: run once after the suite
  -> [TestTree (WebDriver m ())]
  -> m ()
runSuites config caps setup teardown suites = do
  runSession config $ runIsolated caps $ do
    setup
    mapM_ runTestTree suites
    teardown
  return ()


-- | Run a list of `TestTree`s, returning a summary of any assertions made.
debugSuites
  :: (Effectful m)
  => WebDriverConfig
  -> Capabilities
  -> WebDriver m () -- ^ Setup: run once before the suite (for logging in, etc.)
  -> WebDriver m () -- ^ Teardown: run once after the suite
  -> [TestTree (WebDriver m ())] -- ^ List of test trees to be run
  -> m AssertionSummary
debugSuites config caps setup teardown suites = do
  assertions <- debugSession config $ runIsolated caps $ do
    setup
    mapM_ runTestTree suites
    teardown
  return $ summarize assertions


-- | Save all cookies for the current domain to a given file.
stashCookies
  :: (Effectful m)
  => FilePath
  -> WebDriver m ()
stashCookies file =
  getAllCookies >>= writeCookieFile file


-- | Load cookies from a file saved with `stashCookies`. Returns `False` if the cookie file is missing or cannot be read.
loadCookies
  :: (Effectful m)
  => FilePath
  -> WebDriver m Bool
loadCookies file = do
  file <- readCookieFile file
  case file of
    Nothing -> return False
    Just cs -> do
      mapM addCookie cs
      return True


-- | Write cookies to a file under the secrets path. 
writeCookieFile
  :: (Effectful m)
  => FilePath -- ^ File path; relative to @$SECRETS_PATH/cookies/@
  -> [Cookie]
  -> WebDriver m ()
writeCookieFile file cookies = do
  path <- getEnvironment >>= theClientEnvironment >>= theSecretsPath
  let fullpath = path ++ "/cookies/" ++ file
  writeFilePath fullpath (Aeson.encode cookies)


-- | Read cookies from a file stored with `writeCookieFile`. Returns `Nothing` if the file does not exist.
readCookieFile
  :: (Effectful m)
  => FilePath -- ^ File path; relative to @$SECRETS_PATH/cookies/@
  -> WebDriver m (Maybe [Cookie])
readCookieFile file = do
  path <- getEnvironment >>= theClientEnvironment >>= theSecretsPath
  let fullpath = path ++ "/cookies/" ++ file
  cookieFileExists <- mFileExists fullpath
  if cookieFileExists
    then readFilePath fullpath
      >>= mParseJson
      >>= constructFromJSON
      >>= mapM constructFromJSON
      >>= (return . Just)
    else return Nothing


-- | `KeyDownAction` with the given `Char`.
keypress :: Char -> ActionItem
keypress x = emptyActionItem
  { _action_type = Just KeyDownAction
  , _action_value = Just [x]
  }


-- | Simulate pressing a `Key`.
press :: Key -> Action
press key = emptyAction
  { _input_source_type = Just KeyInputSource
  , _input_source_id = Just "kbd"
  , _action_items = [keypress (keyToChar key)]
  }


-- | Simulate typing some text.
typeString :: String -> Action
typeString x = emptyAction
  { _input_source_type = Just KeyInputSource
  , _input_source_id = Just "kbd"
  , _action_items = map keypress x
  }