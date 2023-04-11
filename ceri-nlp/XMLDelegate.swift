//
//  XMLDelegate.swift
//  ceri-nlp
//
//  Created by Soren Marcelino on 02/04/2023.
//

import Foundation

class XMLDelegate: NSObject, XMLParserDelegate {
    var currentElement: String?
    var text: String = ""
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            currentElement = elementName
            text = ""
        }
    
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }
        
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        currentElement = nil
        if elementName == "transciption" {
            print("T:\(text)")
        }
    }
}
