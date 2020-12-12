//  ViewRecorder.swift
//
//  Created by patrick piemonte on 6/13/19.
//
//  The MIT License (MIT)
//
//  Copyright (c) 2019-present patrick piemonte (http://patrickpiemonte.com/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import UIKit
import Foundation
import AVFoundation

public enum ViewRecorderError: Error, CustomStringConvertible {
    case cancelled
    case noOutputFile
    
    public var description: String {
        get {
            switch self {
            case .cancelled:
                return "Cancelled"
            case .noOutputFile:
                return "No Output File"
            }
        }
    }
}

/// https://github.com/NextLevel/ViewRecorder
public final class ViewRecorder {
    
    // MARK: - types
    
    public typealias ProgressHandler = (_ progress: Float) -> Void
    public typealias ResultHandler = (Swift.Result<URL, Error>) -> Void
    
    // MARK: - properties
    
    public var outputFileUrl: URL? {
        didSet {
            self._videoWriter.outputFileUrl = self.outputFileUrl
        }
    }
    
    public var framesPerSecond: Int32 = 60 {
        didSet {
            self._videoWriter.framesPerSecond = self.framesPerSecond
        }
    }
    
    // MARK: - ivars
    
    fileprivate var _videoWriter: VideoWriter = VideoWriter()
    fileprivate var _sourceView: UIView?
    fileprivate var _progressHandler: ProgressHandler?
    fileprivate var _completionHandler: ResultHandler?
    
    fileprivate var _source: DispatchSourceTimer?
    fileprivate var _queue: DispatchQueue = DispatchQueue(label: "com.patrickpiemonte.ViewRecorder",
                                                          qos: .userInitiated,
                                                          autoreleaseFrequency: .workItem,
                                                          target: DispatchQueue.global())

    // MARK: - object lifecycle
    
    public init() {
    }
    
    deinit {
        self._sourceView = nil
        self._progressHandler = nil
        self._completionHandler = nil
    }
    
}

// MARK: - actions

extension ViewRecorder {
    
    public func startRecording(view: UIView, progressHandler: ViewRecorder.ProgressHandler? = nil,  completionHandler: ViewRecorder.ResultHandler? = nil) {
        self._sourceView = view
        self._videoWriter.outputSize = view.bounds.size
        self._progressHandler = progressHandler
        self._completionHandler = completionHandler
               
        self._videoWriter.startDate = Date()
        self._source = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(), queue: self._queue)
        self._source?.setEventHandler(handler: { [weak self] in
            DispatchQueue.main.sync {
                let progress: Float = 0.0
                self?._progressHandler?(progress)

                guard let sourceView = self?._sourceView else {
                    return
                }
                guard let image = self?.image(fromView: sourceView) else {
                    return
                }
                self?._videoWriter.writeFrame(image: image)
            }
        })
        self._source?.setCancelHandler(handler: { [weak self] in
            DispatchQueue.main.sync {
                self?._videoWriter.finish {
                    DispatchQueue.main.async {
                        if let url = self?._videoWriter.outputFileUrl {
                            self?._completionHandler?(.success(url))
                        } else {
                            self?._completionHandler?(.failure(ViewRecorderError.cancelled))
                        }
                    }
                }
            }
        })
        
        let repeatingTime: Int = Int(1000 / (self.framesPerSecond))
        self._source?.schedule(deadline: .now(), repeating: DispatchTimeInterval.milliseconds(repeatingTime))
        self._source?.resume()
    }
    
    public func stop() {
        self._source?.cancel()
        self._source = nil
        self._videoWriter.endDate = Date()
    }

}

extension ViewRecorder {
    
    fileprivate func image(fromView view: UIView) -> UIImage? {
        autoreleasepool { () -> UIImage? in
            UIGraphicsBeginImageContextWithOptions(view.frame.size, true, 0)
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            let rasterizedView = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return rasterizedView
        }
    }
    
}

public final class VideoWriter {
 
    // MARK: - config
    
    public var outputSize: CGSize = .zero
    public var outputFileUrl: URL?

    public var framesPerSecond: Int32 = 120
    public var startDate: Date?
    public var endDate: Date?
    
    // MARK: - ivars
    
    fileprivate var _firstFrame: CFAbsoluteTime?
    fileprivate var _timestamp: TimeInterval?
    fileprivate var _frameCount: UInt64 = 0
    fileprivate var _queue: DispatchQueue = DispatchQueue(label: "com.patrickpiemonte.VideoWriter",
                                                            qos: .userInitiated,
                                                            autoreleaseFrequency: .workItem,
                                                            target: DispatchQueue.global())
    
    fileprivate var _bufferCount: Int64 = 0
    fileprivate var _assetWriter: AVAssetWriter?
    fileprivate var _assetWriterVideoInput: AVAssetWriterInput?
    fileprivate var _assetWriterPixelBufferInputAdapter: AVAssetWriterInputPixelBufferAdaptor?
    
    // MARK: - object lifecycle
    
    public init() {
    }

}

extension VideoWriter {

    fileprivate func createPixelBuffer(fromImage image: UIImage) -> CVPixelBuffer? {
        autoreleasepool { () -> CVPixelBuffer? in
            guard let pixelBufferPool = self._assetWriterPixelBufferInputAdapter?.pixelBufferPool else {
                return nil
            }
            
            var buffer: CVPixelBuffer? = nil
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &buffer) == kCVReturnSuccess else {
                return nil
            }

            guard let pixelBuffer = buffer else {
                return nil
            }
                    
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
            
            let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
            let contextSize = image.size
            
            if let context = CGContext(data: pixelData,
                                       width: Int(contextSize.width),
                                       height: Int(contextSize.height),
                                       bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                       space: rgbColorSpace,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
              var imageWidth = image.size.width
              var imageHeight = image.size.height

              if Int(imageHeight) > context.height {
                imageHeight = 16 * (CGFloat(context.height) / 16).rounded(.awayFromZero)
              } else if Int(imageWidth) > context.width {
                imageWidth = 16 * (CGFloat(context.width) / 16).rounded(.awayFromZero)
              }
              
              context.clear(CGRect(x: 0.0, y: 0.0, width: imageWidth, height: imageHeight))
              context.setFillColor(UIColor.black.cgColor)
              context.fill(CGRect(x: 0.0, y: 0.0, width: CGFloat(context.width), height: CGFloat(context.height)))
              context.concatenate(.identity)
              
              if let cgImage = image.cgImage {
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
              }
              
              CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
            }
            
            return pixelBuffer
        }
    }
    
}

extension VideoWriter {
    
    fileprivate func setupVideoWriterIfNecessary(withImage image: UIImage) {
          guard self._assetWriter == nil,
                let outputFileUrl = self.outputFileUrl,
                self.outputSize != .zero else {
              return
          }
          
          do {
              self._assetWriter = try AVAssetWriter(outputURL: outputFileUrl, fileType: AVFileType.mp4)
          } catch let error {
              print("failed \(error)")
              return
          }
          
          guard let assetWriter = self._assetWriter else {
              return
          }

          let outputSettings: [String: Any] = [ AVVideoCodecKey : AVVideoCodecType.h264,
                                                AVVideoWidthKey : outputSize.width,
                                                AVVideoHeightKey : outputSize.height]
          self._assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
          if let assetWriterVideoInput = self._assetWriterVideoInput {
              assetWriterVideoInput.expectsMediaDataInRealTime = true

              let sourcePixelBufferAttributes: [String: Any] = [ kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32ARGB,
                                                                 kCVPixelBufferWidthKey as String : outputSize.width,
                                                                 kCVPixelBufferHeightKey as String : outputSize.height,
                                                                 kCVPixelBufferCGImageCompatibilityKey as String : NSNumber(booleanLiteral: true),
                                                                 kCVPixelBufferCGBitmapContextCompatibilityKey as String : NSNumber(booleanLiteral: true) ]

              self._assetWriterPixelBufferInputAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput,
                                                                                       sourcePixelBufferAttributes: sourcePixelBufferAttributes)
              assetWriter.add(assetWriterVideoInput)
              self._firstFrame = CFAbsoluteTimeGetCurrent()
          }

          if assetWriter.startWriting() {
              assetWriter.startSession(atSourceTime: CMTime.zero)
          }
    }
    
    public func writeFrame(image: UIImage) {
        self._queue.async {
            self.setupVideoWriterIfNecessary(withImage: image)
            if self._assetWriterVideoInput?.isReadyForMoreMediaData ?? false {
                let presentationTime = CMTime(value: self._bufferCount, timescale: self.framesPerSecond)
                if let pixelBuffer = self.createPixelBuffer(fromImage: image) {
                    self._assetWriterPixelBufferInputAdapter?.append(pixelBuffer, withPresentationTime: presentationTime)
                    self._bufferCount = self._bufferCount + 1
                }
            }
        }
    }
    
    public func finish(completionHandler: (()-> Void)? = nil) {
        self._queue.async {
            self._assetWriterVideoInput?.markAsFinished()
            self._assetWriter?.finishWriting(completionHandler: {
                self._assetWriterVideoInput = nil
                self._assetWriterPixelBufferInputAdapter = nil
                DispatchQueue.main.async {
                    completionHandler?()
                }
            })
        }
    }
}
