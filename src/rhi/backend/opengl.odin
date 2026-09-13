package backend

import "../../platform/graphics"
import driver "opengl"

when !graphics.METAL {
	Device_Context :: driver.Device_Context
	SHADER_LANGUAGE :: driver.SHADER_LANGUAGE
	Device :: driver.Device
	Buffer :: driver.Buffer
	Texture :: driver.Texture
	Render_Target :: driver.Render_Target
	Shader :: driver.Shader
	Pipeline :: driver.Pipeline
	create_device :: driver.create_device
	validate_context :: driver.validate_context
	destroy_device :: driver.destroy_device
	begin_frame :: driver.begin_frame
	end_frame :: driver.end_frame
	wait_idle :: driver.wait_idle
	create_buffer :: driver.create_buffer
	update_buffer :: driver.update_buffer
	destroy_buffer :: driver.destroy_buffer
	create_texture :: driver.create_texture
	destroy_texture :: driver.destroy_texture
	create_render_target :: driver.create_render_target
	destroy_render_target :: driver.destroy_render_target
	create_shader :: driver.create_shader
	destroy_shader :: driver.destroy_shader
	create_pipeline :: driver.create_pipeline
	destroy_pipeline :: driver.destroy_pipeline
	pipeline_requirements :: driver.pipeline_requirements
	begin_pass :: driver.begin_pass
	end_pass :: driver.end_pass
	draw_indexed :: driver.draw_indexed
}
