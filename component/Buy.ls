require! \./Component.ls
require! \./ParallaxButton.ls

{templates} = require \../build/component-jade.js

module.exports =
  class Buy extends Component
    component-name: \Buy
    template: templates.Buy
    children: [new ParallaxButton {title: 'Buy MOFO BUY!'} \#buy]
