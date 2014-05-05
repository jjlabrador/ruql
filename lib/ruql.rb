# basic gems/libs we rely on
require 'builder'
require 'logger'

$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__)))

# renderers
require 'ruql/renderers/xml_renderer'
require 'ruql/renderers/html5_renderer'
require 'ruql/renderers/html_form_renderer'
require 'ruql/renderers/edxml_renderer'
require 'ruql/renderers/auto_qcm_renderer'
require 'ruql/renderers/json_renderer'

# question types
require 'ruql/quiz'
require 'ruql/question'
require 'ruql/answer'
require 'ruql/multiple_choice'
require 'ruql/select_multiple'
require 'ruql/true_false'
require 'ruql/fill_in'
require 'ruql/version'
require 'ruql/js'
require 'ruql/drag_drop_fill_in'
require 'ruql/drag_drop_multiple_choice'
require 'ruql/drag_drop_select_multiple'
require 'ruql/programming'