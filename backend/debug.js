const fs = require('fs');
try {
  require('./index.js');
} catch (e) {
  fs.writeFileSync('error_msg.txt', e.toString() + '\n' + e.stack);
}
