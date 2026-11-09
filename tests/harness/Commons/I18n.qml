pragma Singleton
import QtQuick
import Quickshell

Singleton {
  property string language: "en"
  property string formatLocale: "en_US"
  function formatNumber(value, decimals) { return Number(value).toFixed(decimals) }
}
