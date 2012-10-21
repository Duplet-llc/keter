{-# LANGUAGE OverloadedStrings #-}
-- | A light-weight, minimalistic reverse HTTP proxy.
module Keter.Proxy
    ( reverseProxy
    , PortLookup
    , reverseProxySsl
    , setDir
    , TLSConfig
    , TLSConfigNoDir
    ) where

import Prelude hiding ((++), FilePath)
import Data.Conduit
import Data.Conduit.Network
import Data.ByteString (ByteString)
import Keter.PortManager (PortEntry (..))
import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
import Keter.SSL
import Network.HTTP.ReverseProxy (rawProxyTo, ProxyDest (ProxyDest), waiToRaw)
import Network.Wai.Application.Static (defaultFileServerSettings, staticApp)
import qualified Network.Wai as Wai
import Network.HTTP.Types (status301)

-- | Mapping from virtual hostname to port number.
type PortLookup = ByteString -> IO (Maybe PortEntry)

reverseProxy :: ServerSettings IO -> PortLookup -> IO ()
reverseProxy settings = runTCPServer settings . withClient

reverseProxySsl :: TLSConfig -> PortLookup -> IO ()
reverseProxySsl settings = runTCPServerTLS settings . withClient

withClient :: PortLookup
           -> Application IO
withClient portLookup =
    rawProxyTo getDest
  where
    getDest headers = do
        mport <- maybe (return Nothing) portLookup $ lookup "host" headers
        case mport of
            Nothing -> return $ Left $ srcToApp $ toResponse []
            Just (PEPort port) -> return $ Right $ ProxyDest "127.0.0.1" port
            Just (PEStatic root) -> return $ Left $ waiToRaw $ staticApp $ defaultFileServerSettings root
            Just (PERedirect host) -> return $ Left $ waiToRaw $ redirectApp host

redirectApp :: ByteString -> Wai.Application
redirectApp host req = return $ Wai.responseLBS
    status301
    [("Location", dest)]
    (L.fromChunks [dest])
  where
    dest = S.concat
        [ "http://"
        , host
        , Wai.rawPathInfo req
        , Wai.rawQueryString req
        ]

srcToApp :: Monad m => Source m ByteString -> Application m
srcToApp src appdata = src $$ appSink appdata

toResponse :: Monad m => [ByteString] -> Source m ByteString
toResponse hosts =
    yield "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<html><head><title>Welcome to Keter</title></head><body><h1>Welcome to Keter</h1><p>The hostname you have provided is not recognized.</p></body></html>"
