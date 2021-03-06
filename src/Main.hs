module Main where

import Network.CGI
import Data.Maybe (isJust)
import Control.Monad
import Data.Either.Utils
import Data.Either
import Diagrams.Prelude
import Diagrams.Backend.SVG
import Text.Blaze.Svg.Renderer.Utf8 (renderSvg)
import qualified Data.ByteString.Lazy.Char8 as B
import Frets.Util
import Frets

-- Constants for now, TODO: allow manual control from the CGI interface.
vs = 0.2
hs = 0.5/5

data XorY = X Int | Y Int

-- | CGI entry-point:
-- Read in the CGI arguments, then either output an appropriate
-- error message, or output the svg of the fretboard scale
-- diagram requested.
-- TODO: Maybe use the error monad transformer here.
cgiMain :: CGI CGIResult
cgiMain = do
    p <- readInput "period" :: CGI (Maybe Int)
    f <- readInput "frets" :: CGI (Maybe Int)
    s <- readInput "scales" :: CGI (Maybe [[Int]])
    t <- readInput "tuning" :: CGI (Maybe [Int])
    x <- readInput "x" :: CGI (Maybe Int)
    y <- readInput "y" :: CGI (Maybe Int)
    
    -- Handle errors parsing the cgi arguments
    case (handleCGIParseErrs p f s t x y) of 
        Left err                              -> output err
        Right (period,frets,scales,tuning,xy) -> do
            let _fretboard = mkFret tuning period
            let _scales    = map (mkScl period) scales
            case (handleScaleFretboardErrs _fretboard _scales) of
                Left err                 -> output err
                Right (fretboard,scales) -> do
                    let diagrams = map (\scale -> toBoard frets vs hs (chScale fretboard scale)) scales
                    case xy of
                        X x -> output $ foldl1 (\x y -> x++"\n &nbsp;&nbsp;&nbsp; \n"++y) $ map (format (X x)) diagrams
                        Y y -> output $ foldl1 (\x y -> x++"\n &nbsp;&nbsp;&nbsp; \n"++y) $ map (format (Y y)) diagrams

-- | Generate the formatted SVG output from a diagram.
format :: XorY -> Diagram B R2 -> String
format (X x) d = B.unpack $ renderSvg $ renderDia SVG (SVGOptions (Width (fromIntegral x)) Nothing) d
format (Y y) d = B.unpack $ renderSvg $ renderDia SVG (SVGOptions (Height (fromIntegral y)) Nothing) d

-- | Handle the error messages from parsing the arguments.
handleCGIParseErrs :: Maybe Int -> Maybe Int -> Maybe [[Int]]
       -> Maybe [Int] -> Maybe Int -> Maybe Int
       -> (Either String (Int,Int,[[Int]],[Int],XorY))
handleCGIParseErrs p f s t x y 
  -- Valid format
  | Just p' <- p
  , Just f' <- f
  , Just s' <- s
  , Just t' <- t
  , isJust x `xor` isJust y
  = case (x,y) of 
       (Just x',_) -> Right (p',f',s',t',X x')
       (_,Just y') -> Right (p',f',s',t',Y y')
  -- Errors, invalid format
  |  otherwise
  = collectErrors [(p == Nothing, "Error parsing period, should be an integer"),
                   (f == Nothing, "Error parsing frets, should be an integer"),
                   (s == Nothing, "Error parsing scales, should be a list of a list of integers (e.a. [[1,2,3],[4,5,6]])"),
                   (t == Nothing, "Error parsing tuning, should be a list of integers, (e.a. [1,2,3])"),
                   ((x == Nothing) && (y == Nothing), "Neither given an x, nor a y"),
                   ((isJust x) && (isJust y), "Given both an x and a y, only one or the other can be given")]

-- | Handle the error messages from constructing the scales and fretboard
handleScaleFretboardErrs :: Either [String] Fretboard -> [Either [String] Scale] -> Either String (Fretboard,[Scale])
handleScaleFretboardErrs _fb _scls | isRight _fb
                                   , all (==True) (map isRight _scls)
                                   = Right (fromRight _fb,map fromRight _scls)
                                   -- Remove redundant error messages when period is invalid
                                   | isLeft _fb
                                   , "Period must be a positive number" `elem` (fromLeft _fb)
                                   = concatErrors $ (fromLeft _fb)
                                   | isLeft _fb
                                   = concatErrors $ (fromLeft _fb) ++ (indexErrs _scls)
                                   | otherwise = concatErrors (indexErrs _scls)

-- | Include which no. scale the errors are coming from.
indexErrs :: [Either [String] a] -> [String]
indexErrs xs = go 1 xs []
    where go n [] idx = idx
          go n ((Left errs):xs) idx = go (n+1) xs (idx++["For scale #"++(show n)++": "++(fmt errs)])
          go n ((Right _):xs)   idx = go (n+1) xs idx
          
          fmt errs = (foldl1 (\x y -> x++", "++y) errs)



main :: IO ()
main = runCGI (handleErrors cgiMain)
